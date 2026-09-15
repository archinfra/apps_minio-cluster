#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="silo-cluster"
VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
SOURCE_ENV="${ROOT_DIR}/SILO_SOURCE.env"
CHART_DIR="${ROOT_DIR}/charts/silo"
IMAGE_INDEX="${ROOT_DIR}/images/silo-image-index.tsv"
TEMP_DIR="${ROOT_DIR}/.build-silo"
SOURCE_DIR="${TEMP_DIR}/source"
PAYLOAD_DIR="${TEMP_DIR}/payload"
PAYLOAD_FILE="${TEMP_DIR}/payload.tar.gz"
DIST_DIR="${ROOT_DIR}/dist"
INSTALLER_TEMPLATE="${ROOT_DIR}/install-silo.sh"

ARCH="amd64"
PLATFORM="linux/amd64"
BUILD_ALL="false"

log() { printf '[INFO] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

cleanup() { rm -rf "${TEMP_DIR}"; }
trap cleanup EXIT

usage() {
  cat <<EOF
Usage:
  ./build-silo.sh [--arch amd64|arm64|all]

Builds the pinned, security-fixed SILO source commit and packages an offline
installer. The build host does not require jq; customer runtime does not require jq.
EOF
}

normalize_arch() {
  case "$1" in
    amd64|x86_64) ARCH="amd64"; PLATFORM="linux/amd64"; BUILD_ALL="false" ;;
    arm64|aarch64) ARCH="arm64"; PLATFORM="linux/arm64"; BUILD_ALL="false" ;;
    all) BUILD_ALL="true" ;;
    *) die "unsupported arch: $1" ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arch|-a) [[ $# -ge 2 ]] || die "missing value for $1"; normalize_arch "$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
}

load_source_metadata() {
  [[ -f "${SOURCE_ENV}" ]] || die "missing ${SOURCE_ENV}"
  # shellcheck disable=SC1090
  source "${SOURCE_ENV}"
  : "${SILO_SOURCE_REPO:?missing SILO_SOURCE_REPO}"
  : "${SILO_SOURCE_COMMIT:?missing SILO_SOURCE_COMMIT}"
  : "${SILO_BASE_RELEASE:?missing SILO_BASE_RELEASE}"
  : "${SILO_SECURITY_ADVISORY:?missing SILO_SECURITY_ADVISORY}"
  : "${SILO_IMAGE_TAG:?missing SILO_IMAGE_TAG}"
}

check_requirements() {
  command -v docker >/dev/null 2>&1 || die "docker is required"
  command -v git >/dev/null 2>&1 || die "git is required"
  command -v go >/dev/null 2>&1 || die "go is required"
  command -v make >/dev/null 2>&1 || die "make is required"
  command -v tar >/dev/null 2>&1 || die "tar is required"
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"
  [[ -f "${IMAGE_INDEX}" ]] || die "missing ${IMAGE_INDEX}"
  [[ -d "${CHART_DIR}" ]] || die "missing ${CHART_DIR}"
  [[ -f "${INSTALLER_TEMPLATE}" ]] || die "missing ${INSTALLER_TEMPLATE}"
  grep -q '^__PAYLOAD_BELOW__$' "${INSTALLER_TEMPLATE}" || die "installer payload marker missing"
}

prepare_dirs() {
  rm -rf "${PAYLOAD_DIR}" "${PAYLOAD_FILE}"
  mkdir -p "${PAYLOAD_DIR}/charts" "${PAYLOAD_DIR}/images" "${PAYLOAD_DIR}/meta" "${PAYLOAD_DIR}/docs" "${DIST_DIR}"
  cp -R "${CHART_DIR}" "${PAYLOAD_DIR}/charts/"
  cp "${ROOT_DIR}/VERSION" "${SOURCE_ENV}" "${ROOT_DIR}/THIRD_PARTY_NOTICES.md" "${PAYLOAD_DIR}/meta/"
  cp "${ROOT_DIR}/docs/SILO_BASELINE.md" "${PAYLOAD_DIR}/docs/"
  if [[ -f "${ROOT_DIR}/docs/SILO_RELEASE_0.2.0.md" ]]; then
    cp "${ROOT_DIR}/docs/SILO_RELEASE_0.2.0.md" "${PAYLOAD_DIR}/docs/"
  fi
  if [[ -f "${ROOT_DIR}/scripts/silo-mc-smoke.sh" ]]; then
    cp "${ROOT_DIR}/scripts/silo-mc-smoke.sh" "${PAYLOAD_DIR}/docs/"
  fi
  : > "${PAYLOAD_DIR}/images/image-index.tsv"
}

prepare_source() {
  rm -rf "${SOURCE_DIR}"
  mkdir -p "${SOURCE_DIR}"
  local source_repo="${SILO_SOURCE_REPO_OVERRIDE:-${SILO_SOURCE_REPO}}"
  log "Fetching SILO source ${SILO_SOURCE_COMMIT} from ${source_repo}"
  git -C "${SOURCE_DIR}" init -q
  git -C "${SOURCE_DIR}" remote add origin "${source_repo}"
  git -C "${SOURCE_DIR}" fetch -q --depth 1 origin "${SILO_SOURCE_COMMIT}"
  git -C "${SOURCE_DIR}" checkout -q --detach FETCH_HEAD
  local actual
  actual="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
  [[ "${actual}" == "${SILO_SOURCE_COMMIT}" ]] || die "source commit mismatch: ${actual}"
}

build_image() {
  local arch="$1"
  local local_ref="$2"
  log "Building SILO ${SILO_SOURCE_COMMIT} for linux/${arch} -> ${local_ref}"
  (
    cd "${SOURCE_DIR}"
    make docker GOARCH="${arch}" TAG="${local_ref}"
  )
  docker image inspect "${local_ref}" >/dev/null
}

prepare_image() {
  local wanted_arch="$1"
  local wanted_platform="$2"
  local count=0
  local arch platform target_ref tar_name rest

  while IFS=$'\t' read -r arch platform target_ref tar_name rest; do
    [[ -n "${arch}" ]] || continue
    [[ "${arch:0:1}" != "#" ]] || continue
    [[ "${arch}" == "${wanted_arch}" ]] || continue
    [[ "${platform}" == "${wanted_platform}" ]] || die "platform mismatch for ${arch}: ${platform}"

    local local_ref="archinfra-payload/silo:${VERSION}-${wanted_arch}"
    prepare_source
    build_image "${wanted_arch}" "${local_ref}"

    log "Saving ${local_ref} -> ${tar_name}"
    docker save -o "${PAYLOAD_DIR}/images/${tar_name}" "${local_ref}"
    printf '%s\t%s\t%s\n' "${tar_name}" "${local_ref}" "${target_ref}" >> "${PAYLOAD_DIR}/images/image-index.tsv"
    count=$((count + 1))
  done < "${IMAGE_INDEX}"

  (( count > 0 )) || die "no image definition for ${wanted_arch}"
}

package_one() {
  local arch="$1"
  local platform="$2"
  prepare_dirs
  prepare_image "${arch}" "${platform}"

  tar -C "${PAYLOAD_DIR}" -czf "${PAYLOAD_FILE}" .
  tar -tzf "${PAYLOAD_FILE}" >/dev/null

  local out="${DIST_DIR}/${APP_NAME}-installer-${VERSION}-${arch}.run"
  cat "${INSTALLER_TEMPLATE}" "${PAYLOAD_FILE}" > "${out}"
  chmod +x "${out}"
  (
    cd "${DIST_DIR}"
    sha256sum "$(basename "${out}")" > "$(basename "${out}").sha256"
  )

  log "Generated ${out}"
}

main() {
  parse_args "$@"
  load_source_metadata
  check_requirements
  log "SILO base release: ${SILO_BASE_RELEASE}"
  log "Security advisory: ${SILO_SECURITY_ADVISORY}"
  log "Pinned source: ${SILO_SOURCE_COMMIT}"
  if [[ "${BUILD_ALL}" == "true" ]]; then
    package_one amd64 linux/amd64
    package_one arm64 linux/arm64
  else
    package_one "${ARCH}" "${PLATFORM}"
  fi
}

main "$@"
