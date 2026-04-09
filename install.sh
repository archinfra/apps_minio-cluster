#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="minio-cluster"
APP_VERSION="0.1.0"
PACKAGE_PROFILE="integrated"
WORKDIR="/tmp/${APP_NAME}-installer"
CHART_DIR="${WORKDIR}/charts/minio"
IMAGE_DIR="${WORKDIR}/images"
IMAGE_INDEX="${IMAGE_DIR}/image-index.tsv"

ACTION="help"
RELEASE_NAME="minio"
NAMESPACE="aict"
ACCESS_KEY="minioadmin"
SECRET_KEY="minioadmin@123"
MODE="distributed"
MINIO_REPLICAS="4"
DRIVES_PER_NODE="1"
MINIO_STORAGE_CLASS="nfs"
MINIO_STORAGE_SIZE="500Gi"
SERVICE_TYPE="NodePort"
API_NODE_PORT="9000"
CONSOLE_ENABLED="true"
CONSOLE_SERVICE_TYPE="NodePort"
CONSOLE_NODE_PORT="9090"
ENABLE_METRICS="false"
ENABLE_SERVICEMONITOR="false"
SERVICE_MONITOR_NAMESPACE=""
SERVICE_MONITOR_INTERVAL="30s"
SERVICE_MONITOR_SCRAPE_TIMEOUT=""
IMAGE_PULL_POLICY="IfNotPresent"
WAIT_TIMEOUT="10m"
REGISTRY_REPO="sealos.hub:5000/kube4"
REGISTRY_REPO_EXPLICIT="false"
REGISTRY_USER="admin"
REGISTRY_PASS="passw0rd"
SKIP_IMAGE_PREPARE="false"
AUTO_YES="false"

MINIO_REQUEST_CPU="${MINIO_REQUEST_CPU:-500m}"
MINIO_REQUEST_MEM="${MINIO_REQUEST_MEM:-1Gi}"
MINIO_LIMIT_CPU="${MINIO_LIMIT_CPU:-4}"
MINIO_LIMIT_MEM="${MINIO_LIMIT_MEM:-8Gi}"

MINIO_CONSOLE_REQUEST_CPU="${MINIO_CONSOLE_REQUEST_CPU:-100m}"
MINIO_CONSOLE_REQUEST_MEM="${MINIO_CONSOLE_REQUEST_MEM:-256Mi}"
MINIO_CONSOLE_LIMIT_CPU="${MINIO_CONSOLE_LIMIT_CPU:-500m}"
MINIO_CONSOLE_LIMIT_MEM="${MINIO_CONSOLE_LIMIT_MEM:-512Mi}"

MINIO_MC_REQUEST_CPU="${MINIO_MC_REQUEST_CPU:-50m}"
MINIO_MC_REQUEST_MEM="${MINIO_MC_REQUEST_MEM:-64Mi}"
MINIO_MC_LIMIT_CPU="${MINIO_MC_LIMIT_CPU:-200m}"
MINIO_MC_LIMIT_MEM="${MINIO_MC_LIMIT_MEM:-256Mi}"

HELM_ARGS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() {
  echo -e "${CYAN}[INFO]${NC} $*"
}

success() {
  echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

die() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

section() {
  echo
  echo -e "${BLUE}${BOLD}============================================================${NC}"
  echo -e "${BLUE}${BOLD}$*${NC}"
  echo -e "${BLUE}${BOLD}============================================================${NC}"
}

program_name() {
  basename "$0"
}

banner() {
  echo
  echo -e "${GREEN}${BOLD}MinIO Cluster Offline Installer${NC}"
  echo -e "${CYAN}Version: ${APP_VERSION}${NC}"
  echo -e "${CYAN}Package: ${PACKAGE_PROFILE}${NC}"
}

usage() {
  local cmd="./$(program_name)"
  cat <<EOF
Usage:
  ${cmd} <install|uninstall|status|help> [options] [-- <helm_args>]
  ${cmd} -h|--help

Actions:
  install       Prepare images and install or upgrade the MinIO release
  uninstall     Uninstall the MinIO release
  status        Show Helm release and Kubernetes resource status
  help          Show this message

Core options:
  -n, --namespace <ns>                 Namespace, default: ${NAMESPACE}
  --release-name <name>                Helm release name, default: ${RELEASE_NAME}
  --mode <mode>                        standalone|distributed, default: ${MODE}
  --replicas <num>                     Replica count, default: ${MINIO_REPLICAS}
  --drives-per-node <num>              Drives per node, default: ${DRIVES_PER_NODE}
  --access-key <key>                   MinIO access key, default: ${ACCESS_KEY}
  --secret-key <key>                   MinIO secret key, default: <hidden>
  --storage-class <name>               StorageClass, default: ${MINIO_STORAGE_CLASS}
  --storage-size <size>                PVC size, default: ${MINIO_STORAGE_SIZE}
  --service-type <type>                NodePort|ClusterIP|LoadBalancer, default: ${SERVICE_TYPE}
  --api-node-port <port>               API NodePort, default: ${API_NODE_PORT}
  --console-service-type <type>        Console service type, default: ${CONSOLE_SERVICE_TYPE}
  --console-node-port <port>           Console NodePort, default: ${CONSOLE_NODE_PORT}
  --disable-console                    Disable MinIO console

Monitoring:
  --enable-metrics                     Enable MinIO metrics endpoint exposure
  --disable-metrics                    Disable MinIO metrics endpoint exposure
  --enable-servicemonitor              Create ServiceMonitor and auto-enable metrics
  --disable-servicemonitor             Disable ServiceMonitor
  --service-monitor-namespace <ns>     Optional namespace for the ServiceMonitor
  --service-monitor-interval <value>   ServiceMonitor interval, default: ${SERVICE_MONITOR_INTERVAL}
  --service-monitor-scrape-timeout <v> ServiceMonitor scrape timeout

MinIO server resources:
  --minio-request-cpu <value>          Default: ${MINIO_REQUEST_CPU}
  --minio-request-mem <value>          Default: ${MINIO_REQUEST_MEM}
  --minio-limit-cpu <value>            Default: ${MINIO_LIMIT_CPU}
  --minio-limit-mem <value>            Default: ${MINIO_LIMIT_MEM}

Console resources:
  --console-request-cpu <value>        Default: ${MINIO_CONSOLE_REQUEST_CPU}
  --console-request-mem <value>        Default: ${MINIO_CONSOLE_REQUEST_MEM}
  --console-limit-cpu <value>          Default: ${MINIO_CONSOLE_LIMIT_CPU}
  --console-limit-mem <value>          Default: ${MINIO_CONSOLE_LIMIT_MEM}

Provisioning job resources:
  --mc-request-cpu <value>             Default: ${MINIO_MC_REQUEST_CPU}
  --mc-request-mem <value>             Default: ${MINIO_MC_REQUEST_MEM}
  --mc-limit-cpu <value>               Default: ${MINIO_MC_LIMIT_CPU}
  --mc-limit-mem <value>               Default: ${MINIO_MC_LIMIT_MEM}

Image and rollout:
  --registry <repo-prefix>             Target image repo prefix, default: ${REGISTRY_REPO}
  --registry-user <user>               Registry username, default: ${REGISTRY_USER}
  --registry-password <password>       Registry password, default: <hidden>
  --image-pull-policy <policy>         Always|IfNotPresent|Never, default: ${IMAGE_PULL_POLICY}
  --skip-image-prepare                 Reuse images already present in the target registry
  --wait-timeout <duration>            Helm wait timeout, default: ${WAIT_TIMEOUT}

Other:
  -y, --yes                            Skip confirmation
  -h, --help                           Show help

Examples:
  ${cmd} install -y
  ${cmd} install --service-type ClusterIP --disable-console -y
  ${cmd} install --enable-metrics --enable-servicemonitor -y
  ${cmd} install --registry harbor.example.com/kube4 --skip-image-prepare -y
  ${cmd} status -n ${NAMESPACE}
  ${cmd} uninstall -n ${NAMESPACE} -y
EOF
}

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

parse_args() {
  if [[ $# -eq 0 ]]; then
    ACTION="help"
    return
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|uninstall|status|help)
        ACTION="$1"
        shift
        ;;
      -n|--namespace)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        NAMESPACE="$2"
        shift 2
        ;;
      --release-name)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        RELEASE_NAME="$2"
        shift 2
        ;;
      --mode)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MODE="$2"
        shift 2
        ;;
      --replicas)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_REPLICAS="$2"
        shift 2
        ;;
      --drives-per-node)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        DRIVES_PER_NODE="$2"
        shift 2
        ;;
      --access-key)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        ACCESS_KEY="$2"
        shift 2
        ;;
      --secret-key)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        SECRET_KEY="$2"
        shift 2
        ;;
      --storage-class)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_STORAGE_CLASS="$2"
        shift 2
        ;;
      --storage-size)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_STORAGE_SIZE="$2"
        shift 2
        ;;
      --service-type)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        SERVICE_TYPE="$2"
        shift 2
        ;;
      --api-node-port)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        API_NODE_PORT="$2"
        shift 2
        ;;
      --console-service-type)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        CONSOLE_SERVICE_TYPE="$2"
        shift 2
        ;;
      --console-node-port)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        CONSOLE_NODE_PORT="$2"
        shift 2
        ;;
      --disable-console)
        CONSOLE_ENABLED="false"
        shift
        ;;
      --enable-metrics)
        ENABLE_METRICS="true"
        shift
        ;;
      --disable-metrics)
        ENABLE_METRICS="false"
        shift
        ;;
      --enable-servicemonitor)
        ENABLE_SERVICEMONITOR="true"
        shift
        ;;
      --disable-servicemonitor)
        ENABLE_SERVICEMONITOR="false"
        shift
        ;;
      --service-monitor-namespace)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        SERVICE_MONITOR_NAMESPACE="$2"
        shift 2
        ;;
      --service-monitor-interval)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        SERVICE_MONITOR_INTERVAL="$2"
        shift 2
        ;;
      --service-monitor-scrape-timeout)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        SERVICE_MONITOR_SCRAPE_TIMEOUT="$2"
        shift 2
        ;;
      --minio-request-cpu)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_REQUEST_CPU="$2"
        shift 2
        ;;
      --minio-request-mem)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_REQUEST_MEM="$2"
        shift 2
        ;;
      --minio-limit-cpu)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_LIMIT_CPU="$2"
        shift 2
        ;;
      --minio-limit-mem)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_LIMIT_MEM="$2"
        shift 2
        ;;
      --console-request-cpu)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_CONSOLE_REQUEST_CPU="$2"
        shift 2
        ;;
      --console-request-mem)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_CONSOLE_REQUEST_MEM="$2"
        shift 2
        ;;
      --console-limit-cpu)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_CONSOLE_LIMIT_CPU="$2"
        shift 2
        ;;
      --console-limit-mem)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_CONSOLE_LIMIT_MEM="$2"
        shift 2
        ;;
      --mc-request-cpu)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_MC_REQUEST_CPU="$2"
        shift 2
        ;;
      --mc-request-mem)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_MC_REQUEST_MEM="$2"
        shift 2
        ;;
      --mc-limit-cpu)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_MC_LIMIT_CPU="$2"
        shift 2
        ;;
      --mc-limit-mem)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MINIO_MC_LIMIT_MEM="$2"
        shift 2
        ;;
      --registry)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        REGISTRY_REPO="$2"
        REGISTRY_REPO_EXPLICIT="true"
        shift 2
        ;;
      --registry-user)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        REGISTRY_USER="$2"
        shift 2
        ;;
      --registry-password)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        REGISTRY_PASS="$2"
        shift 2
        ;;
      --image-pull-policy)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        IMAGE_PULL_POLICY="$2"
        shift 2
        ;;
      --skip-image-prepare)
        SKIP_IMAGE_PREPARE="true"
        shift
        ;;
      --wait-timeout)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        WAIT_TIMEOUT="$2"
        shift 2
        ;;
      -y|--yes)
        AUTO_YES="true"
        shift
        ;;
      -h|--help)
        ACTION="help"
        shift
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          HELM_ARGS+=("$1")
          shift
        done
        break
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

normalize_flags() {
  case "${MODE}" in
    standalone|distributed) ;;
    *)
      die "Unsupported mode: ${MODE}"
      ;;
  esac

  case "${SERVICE_TYPE}" in
    NodePort|ClusterIP|LoadBalancer) ;;
    *)
      die "Unsupported service type: ${SERVICE_TYPE}"
      ;;
  esac

  case "${CONSOLE_SERVICE_TYPE}" in
    NodePort|ClusterIP|LoadBalancer) ;;
    *)
      die "Unsupported console service type: ${CONSOLE_SERVICE_TYPE}"
      ;;
  esac

  case "${IMAGE_PULL_POLICY}" in
    Always|IfNotPresent|Never) ;;
    *)
      die "Unsupported image pull policy: ${IMAGE_PULL_POLICY}"
      ;;
  esac

  if [[ "${ENABLE_SERVICEMONITOR}" == "true" ]]; then
    ENABLE_METRICS="true"
  fi
}

check_deps() {
  command -v helm >/dev/null 2>&1 || die "helm is required"
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
  if [[ "${ACTION}" == "install" && "${SKIP_IMAGE_PREPARE}" != "true" ]]; then
    command -v docker >/dev/null 2>&1 || die "docker is required unless --skip-image-prepare is used"
  fi
}

confirm() {
  [[ "${AUTO_YES}" == "true" ]] && return 0

  section "Deployment Plan"
  echo "Action                  : ${ACTION}"
  echo "Release                 : ${RELEASE_NAME}"
  echo "Namespace               : ${NAMESPACE}"
  if [[ "${ACTION}" == "install" ]]; then
    echo "Mode                    : ${MODE}"
    echo "Replicas                : ${MINIO_REPLICAS}"
    echo "Drives per node         : ${DRIVES_PER_NODE}"
    echo "StorageClass            : ${MINIO_STORAGE_CLASS}"
    echo "Storage size            : ${MINIO_STORAGE_SIZE}"
    echo "Service type            : ${SERVICE_TYPE}"
    echo "Console enabled         : ${CONSOLE_ENABLED}"
    echo "Metrics                 : ${ENABLE_METRICS}"
    echo "ServiceMonitor          : ${ENABLE_SERVICEMONITOR}"
    echo "Registry repo           : ${REGISTRY_REPO}"
    echo "Skip image prepare      : ${SKIP_IMAGE_PREPARE}"
    echo "Wait timeout            : ${WAIT_TIMEOUT}"
  fi
  echo
  read -r -p "Continue? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || die "Cancelled"
}

payload_start_offset() {
  local marker_line payload_offset skip_bytes byte_hex
  marker_line="$(awk '/^__PAYLOAD_BELOW__$/ { print NR; exit }' "$0")"
  [[ -n "${marker_line}" ]] || die "Unable to locate embedded payload"
  payload_offset="$(( $(head -n "${marker_line}" "$0" | wc -c | tr -d ' ') + 1 ))"

  skip_bytes=0
  while :; do
    byte_hex="$(dd if="$0" bs=1 skip="$((payload_offset + skip_bytes - 1))" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "${byte_hex}" in
      0a|0d)
        skip_bytes=$((skip_bytes + 1))
        ;;
      "")
        die "Installer payload boundary is invalid"
        ;;
      *)
        break
        ;;
    esac
  done

  printf '%s' "$((payload_offset + skip_bytes))"
}

extract_payload() {
  local payload_offset
  payload_offset="$(payload_start_offset)"

  log "Extracting embedded payload to ${WORKDIR}"
  rm -rf "${WORKDIR}"
  mkdir -p "${WORKDIR}"
  tail -c +"${payload_offset}" "$0" | tar -xz -C "${WORKDIR}"

  [[ -d "${CHART_DIR}" ]] || die "Missing chart payload"
  [[ -f "${IMAGE_INDEX}" ]] || die "Missing image metadata payload"
}

image_name_from_ref() {
  local ref="$1"
  local name_tag="${ref##*/}"
  echo "${name_tag%%:*}"
}

image_name_tag_from_ref() {
  local ref="$1"
  echo "${ref##*/}"
}

resolve_target_ref() {
  local default_ref="$1"
  if [[ "${REGISTRY_REPO_EXPLICIT}" == "true" ]]; then
    echo "${REGISTRY_REPO}/$(image_name_tag_from_ref "${default_ref}")"
  else
    echo "${default_ref}"
  fi
}

image_registry_from_ref() {
  local ref="$1"
  echo "${ref%%/*}"
}

image_repository_from_ref() {
  local ref="$1"
  local remainder="${ref#*/}"
  echo "${remainder%:*}"
}

image_tag_from_ref() {
  local ref="$1"
  echo "${ref##*:}"
}

declare -A IMAGE_DEFAULT_TARGETS=()
declare -A IMAGE_EFFECTIVE_TARGETS=()
declare -A IMAGE_LOAD_REFS=()

load_image_metadata() {
  while IFS=$'\t' read -r tar_name load_ref default_target_ref; do
    [[ -n "${tar_name}" ]] || continue
    IMAGE_LOAD_REFS["${tar_name}"]="${load_ref}"
    IMAGE_DEFAULT_TARGETS["${tar_name}"]="${default_target_ref}"
    IMAGE_EFFECTIVE_TARGETS["${tar_name}"]="$(resolve_target_ref "${default_target_ref}")"
  done < "${IMAGE_INDEX}"
}

find_image_ref_by_name() {
  local wanted_name="$1"
  local tar_name
  for tar_name in "${!IMAGE_EFFECTIVE_TARGETS[@]}"; do
    if [[ "$(image_name_from_ref "${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}")" == "${wanted_name}" ]]; then
      echo "${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}"
      return 0
    fi
  done
  return 1
}

docker_image_exists() {
  docker image inspect "$1" >/dev/null 2>&1
}

docker_login() {
  local registry_host="${REGISTRY_REPO%%/*}"
  log "Logging into registry ${registry_host}"
  if ! echo "${REGISTRY_PASS}" | docker login "${registry_host}" -u "${REGISTRY_USER}" --password-stdin >/dev/null 2>&1; then
    warn "docker login failed for ${registry_host}; continuing and letting push decide"
  fi
}

prepare_images() {
  [[ "${SKIP_IMAGE_PREPARE}" == "true" ]] && {
    log "Skipping image prepare because --skip-image-prepare was requested"
    return 0
  }

  docker_login

  local tar_name load_ref default_target_ref target_ref tar_path
  while IFS=$'\t' read -r tar_name load_ref default_target_ref; do
    [[ -n "${tar_name}" ]] || continue
    tar_path="${IMAGE_DIR}/${tar_name}"
    [[ -f "${tar_path}" ]] || die "Missing image tar: ${tar_path}"

    target_ref="${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}"

    if docker_image_exists "${target_ref}"; then
      log "Reusing local image ${target_ref}"
    else
      log "Loading ${tar_name}"
      docker load -i "${tar_path}" >/dev/null

      if [[ "${load_ref}" != "${target_ref}" ]]; then
        log "Tagging ${load_ref} -> ${target_ref}"
        docker tag "${load_ref}" "${target_ref}"
      fi
    fi

    log "Pushing ${target_ref}"
    docker push "${target_ref}" >/dev/null
  done < "${IMAGE_INDEX}"

  success "Image prepare completed"
}

ensure_namespace() {
  if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    log "Creating namespace ${NAMESPACE}"
    kubectl create namespace "${NAMESPACE}" >/dev/null
  fi
}

check_servicemonitor_support() {
  if [[ "${ENABLE_SERVICEMONITOR}" != "true" ]]; then
    return 0
  fi

  if ! kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    warn "ServiceMonitor CRD not found; disabling ServiceMonitor for this install"
    ENABLE_SERVICEMONITOR="false"
  fi
}

preview_command() {
  local rendered=()
  local arg
  for arg in "$@"; do
    rendered+=("$(printf '%q' "${arg}")")
  done
  printf '%s ' "${rendered[@]}"
  echo
}

install_release() {
  local minio_image client_image console_image os_shell_image
  minio_image="$(find_image_ref_by_name "minio")" || die "Unable to resolve minio image"
  client_image="$(find_image_ref_by_name "minio-client")" || die "Unable to resolve minio-client image"
  console_image="$(find_image_ref_by_name "minio-object-browser")" || die "Unable to resolve minio-object-browser image"
  os_shell_image="$(find_image_ref_by_name "os-shell")" || die "Unable to resolve os-shell image"

  local helm_cmd=(
    helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}"
    -n "${NAMESPACE}"
    --create-namespace
    --wait
    --timeout "${WAIT_TIMEOUT}"
    --set-string "mode=${MODE}"
    --set "statefulset.replicaCount=${MINIO_REPLICAS}"
    --set "statefulset.drivesPerNode=${DRIVES_PER_NODE}"
    --set-string "auth.rootUser=${ACCESS_KEY}"
    --set-string "auth.rootPassword=${SECRET_KEY}"
    --set "persistence.enabled=true"
    --set-string "persistence.size=${MINIO_STORAGE_SIZE}"
    --set-string "persistence.storageClass=${MINIO_STORAGE_CLASS}"
    --set-string "global.defaultStorageClass=${MINIO_STORAGE_CLASS}"
    --set "console.enabled=${CONSOLE_ENABLED}"
    --set "metrics.enabled=${ENABLE_METRICS}"
    --set "metrics.serviceMonitor.enabled=${ENABLE_SERVICEMONITOR}"
    --set-string "metrics.serviceMonitor.interval=${SERVICE_MONITOR_INTERVAL}"
    --set-string "image.registry=$(image_registry_from_ref "${minio_image}")"
    --set-string "image.repository=$(image_repository_from_ref "${minio_image}")"
    --set-string "image.tag=$(image_tag_from_ref "${minio_image}")"
    --set-string "image.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "clientImage.registry=$(image_registry_from_ref "${client_image}")"
    --set-string "clientImage.repository=$(image_repository_from_ref "${client_image}")"
    --set-string "clientImage.tag=$(image_tag_from_ref "${client_image}")"
    --set-string "console.image.registry=$(image_registry_from_ref "${console_image}")"
    --set-string "console.image.repository=$(image_repository_from_ref "${console_image}")"
    --set-string "console.image.tag=$(image_tag_from_ref "${console_image}")"
    --set-string "console.image.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "defaultInitContainers.volumePermissions.image.registry=$(image_registry_from_ref "${os_shell_image}")"
    --set-string "defaultInitContainers.volumePermissions.image.repository=$(image_repository_from_ref "${os_shell_image}")"
    --set-string "defaultInitContainers.volumePermissions.image.tag=$(image_tag_from_ref "${os_shell_image}")"
    --set-string "defaultInitContainers.volumePermissions.image.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "resources.requests.cpu=${MINIO_REQUEST_CPU}"
    --set-string "resources.requests.memory=${MINIO_REQUEST_MEM}"
    --set-string "resources.limits.cpu=${MINIO_LIMIT_CPU}"
    --set-string "resources.limits.memory=${MINIO_LIMIT_MEM}"
    --set-string "provisioning.resources.requests.cpu=${MINIO_MC_REQUEST_CPU}"
    --set-string "provisioning.resources.requests.memory=${MINIO_MC_REQUEST_MEM}"
    --set-string "provisioning.resources.limits.cpu=${MINIO_MC_LIMIT_CPU}"
    --set-string "provisioning.resources.limits.memory=${MINIO_MC_LIMIT_MEM}"
    --set-string "service.type=${SERVICE_TYPE}"
  )

  if [[ "${SERVICE_TYPE}" == "NodePort" || "${SERVICE_TYPE}" == "LoadBalancer" ]]; then
    helm_cmd+=(--set-string "service.nodePorts.api=${API_NODE_PORT}")
  fi

  if [[ "${CONSOLE_ENABLED}" == "true" ]]; then
    helm_cmd+=(
      --set-string "console.service.type=${CONSOLE_SERVICE_TYPE}"
      --set-string "console.resources.requests.cpu=${MINIO_CONSOLE_REQUEST_CPU}"
      --set-string "console.resources.requests.memory=${MINIO_CONSOLE_REQUEST_MEM}"
      --set-string "console.resources.limits.cpu=${MINIO_CONSOLE_LIMIT_CPU}"
      --set-string "console.resources.limits.memory=${MINIO_CONSOLE_LIMIT_MEM}"
    )

    if [[ "${CONSOLE_SERVICE_TYPE}" == "NodePort" || "${CONSOLE_SERVICE_TYPE}" == "LoadBalancer" ]]; then
      helm_cmd+=(--set-string "console.service.nodePorts.http=${CONSOLE_NODE_PORT}")
    fi
  fi

  if [[ -n "${SERVICE_MONITOR_NAMESPACE}" && "${ENABLE_SERVICEMONITOR}" == "true" ]]; then
    helm_cmd+=(--set-string "metrics.serviceMonitor.namespace=${SERVICE_MONITOR_NAMESPACE}")
  fi

  if [[ -n "${SERVICE_MONITOR_SCRAPE_TIMEOUT}" && "${ENABLE_SERVICEMONITOR}" == "true" ]]; then
    helm_cmd+=(--set-string "metrics.serviceMonitor.scrapeTimeout=${SERVICE_MONITOR_SCRAPE_TIMEOUT}")
  fi

  if [[ "${ENABLE_SERVICEMONITOR}" == "true" ]]; then
    helm_cmd+=(--set-string "metrics.serviceMonitor.labels.monitoring\\.archinfra\\.io/stack=default")
  fi

  if [[ ${#HELM_ARGS[@]} -gt 0 ]]; then
    helm_cmd+=("${HELM_ARGS[@]}")
  fi

  section "Helm Command Preview"
  preview_command "${helm_cmd[@]}"

  ensure_namespace
  "${helm_cmd[@]}"
  success "MinIO install or upgrade completed"
}

show_post_install_info() {
  section "Deployment Result"
  kubectl get pods,svc,pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true

  if [[ "${ENABLE_SERVICEMONITOR}" == "true" ]] && kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get servicemonitor -n "${SERVICE_MONITOR_NAMESPACE:-${NAMESPACE}}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true
  fi

  if [[ "${SERVICE_TYPE}" == "NodePort" ]]; then
    local node_ip
    node_ip="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}' 2>/dev/null || true)"
    if [[ -n "${node_ip}" ]]; then
      echo
      echo "API      : http://${node_ip}:${API_NODE_PORT}"
      if [[ "${CONSOLE_ENABLED}" == "true" && "${CONSOLE_SERVICE_TYPE}" == "NodePort" ]]; then
        echo "Console  : http://${node_ip}:${CONSOLE_NODE_PORT}"
      fi
    fi
  fi
}

uninstall_release() {
  if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}"
    success "Release ${RELEASE_NAME} uninstalled"
  else
    warn "Helm release ${RELEASE_NAME} not found in namespace ${NAMESPACE}"
  fi
}

show_status() {
  section "Helm Status"
  helm status "${RELEASE_NAME}" -n "${NAMESPACE}" || warn "Release ${RELEASE_NAME} not found"

  section "Kubernetes Resources"
  kubectl get pods,svc,pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true

  if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get servicemonitor -A -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true
  fi
}

main() {
  parse_args "$@"
  normalize_flags
  banner

  case "${ACTION}" in
    help)
      usage
      ;;
    install)
      check_deps
      confirm
      extract_payload
      load_image_metadata
      check_servicemonitor_support
      prepare_images
      install_release
      show_post_install_info
      ;;
    uninstall)
      check_deps
      confirm
      uninstall_release
      ;;
    status)
      check_deps
      show_status
      ;;
    *)
      die "Unsupported action: ${ACTION}"
      ;;
  esac
}

main "$@"
exit 0

__PAYLOAD_BELOW__
