#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="aict"
RELEASE_NAME="silo"
AUTH_SECRET="silo-root-credentials"
ENDPOINT=""
LOCAL_PORT="19000"
INSECURE="false"
KEEP_BUCKET="false"
MC_BIN="${MC_BIN:-}"
PF_PID=""
TMP_DIR=""
ALIAS="archinfra-silo-smoke"
BUCKET=""

log() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  ./scripts/silo-mc-smoke.sh [options]

Validates legacy MinIO client compatibility against SILO using real mc/mcli commands:
  alias set, mb, cp upload, stat, cp download, mirror, rm/rb.

Options:
  -n, --namespace <ns>       default: ${NAMESPACE}
  --release-name <name>      default: ${RELEASE_NAME}
  --auth-secret <name>       default: ${AUTH_SECRET}
  --endpoint <url>           use an existing endpoint instead of kubectl port-forward
  --local-port <port>        default: ${LOCAL_PORT}
  --insecure                 pass --insecure to mc/mcli (for test TLS certs)
  --keep-bucket              do not remove the temporary smoke-test bucket
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--namespace) NAMESPACE="$2"; shift 2 ;;
      --release-name) RELEASE_NAME="$2"; shift 2 ;;
      --auth-secret) AUTH_SECRET="$2"; shift 2 ;;
      --endpoint) ENDPOINT="$2"; shift 2 ;;
      --local-port) LOCAL_PORT="$2"; shift 2 ;;
      --insecure) INSECURE="true"; shift ;;
      --keep-bucket) KEEP_BUCKET="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
}

find_mc() {
  if [[ -n "${MC_BIN}" ]]; then
    command -v "${MC_BIN}" >/dev/null 2>&1 || die "MC_BIN not found: ${MC_BIN}"
    return
  fi
  if command -v mc >/dev/null 2>&1; then
    MC_BIN="mc"
  elif command -v mcli >/dev/null 2>&1; then
    MC_BIN="mcli"
  else
    die "mc or mcli is required"
  fi
}

mc_cmd() {
  if [[ "${INSECURE}" == "true" ]]; then
    "${MC_BIN}" --config-dir "${TMP_DIR}/mc" --insecure "$@"
  else
    "${MC_BIN}" --config-dir "${TMP_DIR}/mc" "$@"
  fi
}

cleanup() {
  set +e
  if [[ -n "${BUCKET}" && "${KEEP_BUCKET}" != "true" && -n "${TMP_DIR}" ]]; then
    mc_cmd rb --force "${ALIAS}/${BUCKET}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${TMP_DIR}" ]]; then
    mc_cmd alias rm "${ALIAS}" >/dev/null 2>&1 || true
    rm -rf "${TMP_DIR}"
  fi
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

start_port_forward() {
  [[ -n "${ENDPOINT}" ]] && return
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required when --endpoint is omitted"
  log "Starting temporary port-forward svc/${RELEASE_NAME} ${LOCAL_PORT}:9000"
  kubectl -n "${NAMESPACE}" port-forward "svc/${RELEASE_NAME}" "${LOCAL_PORT}:9000" >"${TMP_DIR}/port-forward.log" 2>&1 &
  PF_PID=$!
  ENDPOINT="http://127.0.0.1:${LOCAL_PORT}"
}

read_credentials() {
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required to read the credential Secret"
  command -v base64 >/dev/null 2>&1 || die "base64 is required"
  ROOT_USER="$(kubectl -n "${NAMESPACE}" get secret "${AUTH_SECRET}" -o jsonpath='{.data.rootUser}' | base64 -d)"
  ROOT_PASSWORD="$(kubectl -n "${NAMESPACE}" get secret "${AUTH_SECRET}" -o jsonpath='{.data.rootPassword}' | base64 -d)"
  [[ -n "${ROOT_USER}" && -n "${ROOT_PASSWORD}" ]] || die "credential Secret is missing rootUser/rootPassword"
}

wait_for_endpoint() {
  local i
  for i in $(seq 1 30); do
    if mc_cmd alias set "${ALIAS}" "${ENDPOINT}" "${ROOT_USER}" "${ROOT_PASSWORD}" >/dev/null 2>&1; then
      return 0
    fi
    if [[ -n "${PF_PID}" ]] && ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      cat "${TMP_DIR}/port-forward.log" >&2 || true
      die "kubectl port-forward exited"
    fi
    sleep 1
  done
  die "unable to connect to ${ENDPOINT}"
}

run_smoke() {
  BUCKET="archinfra-smoke-$(date +%s)-$$"
  mkdir -p "${TMP_DIR}/src/mirror" "${TMP_DIR}/dst"
  printf 'archinfra-silo-mc-cp-smoke\n' > "${TMP_DIR}/src/probe.txt"
  printf 'archinfra-silo-mc-mirror-smoke\n' > "${TMP_DIR}/src/mirror/mirror.txt"

  log "Creating ${BUCKET}"
  mc_cmd mb "${ALIAS}/${BUCKET}" >/dev/null

  log "Validating legacy mc cp upload/stat/download"
  mc_cmd cp "${TMP_DIR}/src/probe.txt" "${ALIAS}/${BUCKET}/probe.txt" >/dev/null
  mc_cmd stat "${ALIAS}/${BUCKET}/probe.txt" >/dev/null
  mc_cmd cp "${ALIAS}/${BUCKET}/probe.txt" "${TMP_DIR}/dst/probe.txt" >/dev/null
  cmp "${TMP_DIR}/src/probe.txt" "${TMP_DIR}/dst/probe.txt"

  log "Validating mc mirror"
  mc_cmd mirror "${TMP_DIR}/src/mirror" "${ALIAS}/${BUCKET}/mirror" >/dev/null
  mc_cmd cp "${ALIAS}/${BUCKET}/mirror/mirror.txt" "${TMP_DIR}/dst/mirror.txt" >/dev/null
  cmp "${TMP_DIR}/src/mirror/mirror.txt" "${TMP_DIR}/dst/mirror.txt"

  ok "mc/mcli compatibility smoke test passed: cp + stat + mirror"
}

main() {
  parse_args "$@"
  find_mc
  TMP_DIR="$(mktemp -d)"
  mkdir -p "${TMP_DIR}/mc"
  read_credentials
  start_port_forward
  wait_for_endpoint
  run_smoke
}

main "$@"
