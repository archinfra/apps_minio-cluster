#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="silo-cluster"
VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
CHART_DIR="${ROOT_DIR}/charts/silo"
IMAGE_INDEX="${ROOT_DIR}/images/silo-image-index.tsv"
TEMP_DIR="${ROOT_DIR}/.build-silo"
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

Builds an offline SILO installer without jq.
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

check_requirements() {
  command -v docker >/dev/null 2>&1 || die "docker is required"
  command -v tar >/dev/null 2>&1 || die "tar is required"
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"
  [[ -f "${IMAGE_INDEX}" ]] || die "missing ${IMAGE_INDEX}"
  [[ -d "${CHART_DIR}" ]] || die "missing ${CHART_DIR}"
  [[ -f "${INSTALLER_TEMPLATE}" ]] || die "missing ${INSTALLER_TEMPLATE}"
  grep -q '^__PAYLOAD_BELOW__$' "${INSTALLER_TEMPLATE}" || die "installer payload marker missing"
}

prepare_dirs() {
  rm -rf "${TEMP_DIR}"
  mkdir -p "${PAYLOAD_DIR}/charts" "${PAYLOAD_DIR}/images" "${DIST_DIR}"
  cp -R "${CHART_DIR}" "${PAYLOAD_DIR}/charts/"
  : > "${PAYLOAD_DIR}/images/image-index.tsv"
}

prepare_images() {
  local wanted_arch="$1"
  local wanted_platform="$2"
  local count=0
  local arch platform pull_ref target_ref tar_name rest

  while IFS=$'\t' read -r arch platform pull_ref target_ref tar_name rest; do
    [[ -n "${arch}" ]] || continue
    [[ "${arch:0:1}" != "#" ]] || continue
    [[ "${arch}" == "${wanted_arch}" ]] || continue
    [[ "${platform}" == "${wanted_platform}" ]] || die "platform mismatch for ${arch}: ${platform}"

    log "Pulling ${pull_ref} (${platform})"
    docker pull --platform "${platform}" "${pull_ref}" >/dev/null

    local load_ref="archinfra-payload/silo:${VERSION}-${wanted_arch}"
    docker tag "${pull_ref}" "${load_ref}"
    log "Saving ${load_ref} -> ${tar_name}"
    docker save -o "${PAYLOAD_DIR}/images/${tar_name}" "${load_ref}"

    printf '%s\t%s\t%s\n' "${tar_name}" "${load_ref}" "${target_ref}" >> "${PAYLOAD_DIR}/images/image-index.tsv"
    count=$((count + 1))
  done < "${IMAGE_INDEX}"

  (( count > 0 )) || die "no image definition for ${wanted_arch}"
}

package_one() {
  local arch="$1"
  local platform="$2"
  prepare_dirs
  prepare_images "${arch}" "${platform}"

  tar -C "${PAYLOAD_DIR}" -czf "${PAYLOAD_FILE}" .
  tar -tzf "${PAYLOAD_FILE}" >/dev/null

  local out="${DIST_DIR}/${APP_NAME}-installer-${VERSION}-${arch}.run"
  cat "${INSTALLER_TEMPLATE}" "${PAYLOAD_FILE}" > "${out}"
  chmod +x "${out}"
  sha256sum "${out}" | awk '{print $1}' > "${out}.sha256"

  log "Generated ${out}"
}

main() {
  parse_args "$@"
  check_requirements
  if [[ "${BUILD_ALL}" == "true" ]]; then
    package_one amd64 linux/amd64
    package_one arm64 linux/arm64
  else
    package_one "${ARCH}" "${PLATFORM}"
  fi
}

main "$@"
