#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="silo-cluster"
APP_VERSION="0.2.1"
WORKDIR="/tmp/${APP_NAME}-installer"
CHART_DIR="${WORKDIR}/charts/silo"
IMAGE_INDEX="${WORKDIR}/images/image-index.tsv"

ACTION="help"
RELEASE_NAME="silo"
NAMESPACE="aict"
MODE="distributed"
REPLICAS="4"
DRIVES_PER_NODE="1"
STORAGE_CLASS="nfs"
STORAGE_SIZE="500Gi"
SERVICE_TYPE="NodePort"
API_NODE_PORT="30093"
CONSOLE_ENABLED="true"
CONSOLE_SERVICE_TYPE="NodePort"
CONSOLE_NODE_PORT="30092"
AUTH_SECRET="silo-root-credentials"
ROOT_USER="silo-admin"
ROOT_PASSWORD=""
ROOT_PASSWORD_EXPLICIT="false"
TLS_ENABLED="false"
TLS_SECRET=""
RESOURCE_PROFILE="mid"
ENABLE_SERVICEMONITOR="true"
ENABLE_PROMETHEUSRULE="true"
ENABLE_DASHBOARD="true"
NETWORK_POLICY_ENABLED="false"
REGISTRY_REPO="sealos.hub:5000/kube4"
REGISTRY_REPO_EXPLICIT="false"
REGISTRY_USER="admin"
REGISTRY_PASS="passw0rd"
IMAGE_PULL_POLICY="IfNotPresent"
SKIP_IMAGE_PREPARE="false"
WAIT_TIMEOUT="15m"
AUTO_YES="false"

REQUEST_CPU="500m"
REQUEST_MEM="1Gi"
LIMIT_CPU="4"
LIMIT_MEM="8Gi"

log() { printf '\033[0;36m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

usage() {
  cat <<EOF
SILO Cluster Offline Installer ${APP_VERSION}

Usage:
  ./$(basename "$0") <install|status|credentials|endpoint|uninstall|help> [options]

Core:
  -n, --namespace <ns>              default: ${NAMESPACE}
  --release-name <name>             default: ${RELEASE_NAME}
  --mode <standalone|distributed>   default: ${MODE}
  --replicas <n>                    default: ${REPLICAS}
  --drives-per-node <n>             default: ${DRIVES_PER_NODE}
  --storage-class <name>            default: ${STORAGE_CLASS}
  --storage-size <size>             default: ${STORAGE_SIZE}
  --resource-profile <low|mid|high> default: ${RESOURCE_PROFILE}

Credentials:
  --auth-secret <name>              existing/new Secret, default: ${AUTH_SECRET}
  --root-user <user>                used only when the Secret must be created
  --root-password <password>        used only when the Secret must be created
                                    if omitted, a random password is generated
  Existing Secrets are never rotated by this installer.
  'credentials' prints the current Console/S3 root credentials from the Secret.

Exposure:
  --service-type <ClusterIP|NodePort|LoadBalancer>          default: ${SERVICE_TYPE}
  --api-node-port <port>                                    default: ${API_NODE_PORT}
  --console-service-type <ClusterIP|NodePort|LoadBalancer>  default: ${CONSOLE_SERVICE_TYPE}
  --console-node-port <port>                                default: ${CONSOLE_NODE_PORT}
  --disable-console
  'endpoint' prints cluster DNS and NodePort endpoints.

Security:
  --enable-tls --tls-secret <name>  use an existing TLS Secret
  --enable-network-policy           restrict ingress to same namespace by default

Monitoring:
  --disable-servicemonitor
  --disable-prometheusrule
  --disable-dashboard

Images:
  --registry <repo-prefix>          default: ${REGISTRY_REPO}
  --registry-user <user>
  --registry-password <password>
  --image-pull-policy <policy>
  --skip-image-prepare

Other:
  --wait-timeout <duration>         default: ${WAIT_TIMEOUT}
  -y, --yes

Examples:
  ./$(basename "$0") install -y
  ./$(basename "$0") credentials
  ./$(basename "$0") endpoint
  ./$(basename "$0") install --auth-secret existing-s3-admin -y
  ./$(basename "$0") install --enable-tls --tls-secret silo-tls -y
EOF
}

parse_args() {
  [[ $# -gt 0 ]] || return 0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|status|credentials|endpoint|uninstall|help) ACTION="$1"; shift ;;
      -n|--namespace) NAMESPACE="$2"; shift 2 ;;
      --release-name) RELEASE_NAME="$2"; shift 2 ;;
      --mode) MODE="$2"; shift 2 ;;
      --replicas) REPLICAS="$2"; shift 2 ;;
      --drives-per-node) DRIVES_PER_NODE="$2"; shift 2 ;;
      --storage-class) STORAGE_CLASS="$2"; shift 2 ;;
      --storage-size) STORAGE_SIZE="$2"; shift 2 ;;
      --resource-profile) RESOURCE_PROFILE="$2"; shift 2 ;;
      --auth-secret) AUTH_SECRET="$2"; shift 2 ;;
      --root-user) ROOT_USER="$2"; shift 2 ;;
      --root-password) ROOT_PASSWORD="$2"; ROOT_PASSWORD_EXPLICIT="true"; shift 2 ;;
      --service-type) SERVICE_TYPE="$2"; shift 2 ;;
      --api-node-port) API_NODE_PORT="$2"; shift 2 ;;
      --console-service-type) CONSOLE_SERVICE_TYPE="$2"; shift 2 ;;
      --console-node-port) CONSOLE_NODE_PORT="$2"; shift 2 ;;
      --disable-console) CONSOLE_ENABLED="false"; shift ;;
      --enable-tls) TLS_ENABLED="true"; shift ;;
      --tls-secret) TLS_SECRET="$2"; shift 2 ;;
      --enable-network-policy) NETWORK_POLICY_ENABLED="true"; shift ;;
      --disable-servicemonitor) ENABLE_SERVICEMONITOR="false"; shift ;;
      --disable-prometheusrule) ENABLE_PROMETHEUSRULE="false"; shift ;;
      --disable-dashboard) ENABLE_DASHBOARD="false"; shift ;;
      --registry) REGISTRY_REPO="$2"; REGISTRY_REPO_EXPLICIT="true"; shift 2 ;;
      --registry-user) REGISTRY_USER="$2"; shift 2 ;;
      --registry-password) REGISTRY_PASS="$2"; shift 2 ;;
      --image-pull-policy) IMAGE_PULL_POLICY="$2"; shift 2 ;;
      --skip-image-prepare) SKIP_IMAGE_PREPARE="true"; shift ;;
      --wait-timeout) WAIT_TIMEOUT="$2"; shift 2 ;;
      -y|--yes) AUTO_YES="true"; shift ;;
      -h|--help) ACTION="help"; shift ;;
      *) die "unknown argument: $1" ;;
    esac
  done
}

validate() {
  case "${MODE}" in standalone|distributed) ;; *) die "unsupported mode: ${MODE}" ;; esac
  case "${SERVICE_TYPE}" in ClusterIP|NodePort|LoadBalancer) ;; *) die "unsupported service type" ;; esac
  case "${CONSOLE_SERVICE_TYPE}" in ClusterIP|NodePort|LoadBalancer) ;; *) die "unsupported console service type" ;; esac
  case "${IMAGE_PULL_POLICY}" in Always|IfNotPresent|Never) ;; *) die "unsupported image pull policy" ;; esac
  [[ "${REPLICAS}" =~ ^[0-9]+$ ]] || die "replicas must be an integer"
  [[ "${DRIVES_PER_NODE}" =~ ^[0-9]+$ ]] || die "drives-per-node must be an integer"
  [[ "${API_NODE_PORT}" =~ ^[0-9]+$ ]] || die "api node port must be an integer"
  [[ "${CONSOLE_NODE_PORT}" =~ ^[0-9]+$ ]] || die "console node port must be an integer"
  if [[ "${MODE}" == "distributed" ]]; then
    (( REPLICAS >= 4 )) || die "distributed mode requires at least 4 replicas in this delivery baseline"
  else
    REPLICAS="1"
  fi
  if [[ "${TLS_ENABLED}" == "true" && -z "${TLS_SECRET}" ]]; then
    die "--tls-secret is required with --enable-tls"
  fi
  if [[ ( "${SERVICE_TYPE}" != "ClusterIP" || "${CONSOLE_SERVICE_TYPE}" != "ClusterIP" ) && "${TLS_ENABLED}" != "true" ]]; then
    warn "NodePort/LoadBalancer exposure is enabled without TLS; use network controls or enable TLS in production"
  fi
}

apply_profile() {
  case "${RESOURCE_PROFILE,,}" in
    low) REQUEST_CPU="250m"; REQUEST_MEM="512Mi"; LIMIT_CPU="2"; LIMIT_MEM="4Gi" ;;
    mid|midd|medium) RESOURCE_PROFILE="mid" ;;
    high) REQUEST_CPU="1"; REQUEST_MEM="2Gi"; LIMIT_CPU="8"; LIMIT_MEM="16Gi" ;;
    *) die "unsupported resource profile: ${RESOURCE_PROFILE}" ;;
  esac
}

check_deps() {
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
  case "${ACTION}" in
    install)
      command -v helm >/dev/null 2>&1 || die "helm is required"
      command -v tar >/dev/null 2>&1 || die "tar is required"
      command -v od >/dev/null 2>&1 || die "od is required"
      if [[ "${SKIP_IMAGE_PREPARE}" != "true" ]]; then
        command -v docker >/dev/null 2>&1 || die "docker is required unless --skip-image-prepare is used"
      fi
      ;;
    status|uninstall)
      command -v helm >/dev/null 2>&1 || die "helm is required"
      ;;
    credentials)
      command -v base64 >/dev/null 2>&1 || die "base64 is required"
      ;;
  esac
}

payload_start_offset() {
  local marker_line payload_offset skip_bytes byte_hex
  marker_line="$(awk '/^__PAYLOAD_BELOW__$/ { print NR; exit }' "$0")"
  [[ -n "${marker_line}" ]] || die "payload marker not found"
  payload_offset="$(( $(head -n "${marker_line}" "$0" | wc -c | tr -d ' ') + 1 ))"
  skip_bytes=0
  while :; do
    byte_hex="$(dd if="$0" bs=1 skip="$((payload_offset + skip_bytes - 1))" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "${byte_hex}" in
      0a|0d) skip_bytes=$((skip_bytes + 1)) ;;
      "") die "invalid payload boundary" ;;
      *) break ;;
    esac
  done
  printf '%s' "$((payload_offset + skip_bytes))"
}

extract_payload() {
  rm -rf "${WORKDIR}"
  mkdir -p "${WORKDIR}"
  tail -c +"$(payload_start_offset)" "$0" | tar -xz -C "${WORKDIR}"
  [[ -d "${CHART_DIR}" ]] || die "chart payload missing"
  [[ -f "${IMAGE_INDEX}" ]] || die "image index missing"
}

resolve_target_ref() {
  local default_ref="$1"
  if [[ "${REGISTRY_REPO_EXPLICIT}" == "true" ]]; then
    printf '%s/%s\n' "${REGISTRY_REPO}" "${default_ref##*/}"
  else
    printf '%s\n' "${default_ref}"
  fi
}

prepare_images() {
  [[ "${SKIP_IMAGE_PREPARE}" == "true" ]] && return 0
  local host="${REGISTRY_REPO%%/*}"
  printf '%s' "${REGISTRY_PASS}" | docker login "${host}" -u "${REGISTRY_USER}" --password-stdin >/dev/null

  local tar_name load_ref default_ref target_ref
  while IFS=$'\t' read -r tar_name load_ref default_ref; do
    [[ -n "${tar_name}" ]] || continue
    target_ref="$(resolve_target_ref "${default_ref}")"
    docker load -i "${WORKDIR}/images/${tar_name}" >/dev/null
    [[ "${load_ref}" == "${target_ref}" ]] || docker tag "${load_ref}" "${target_ref}"
    docker push "${target_ref}" >/dev/null
  done < "${IMAGE_INDEX}"
}

find_target_image() {
  local tar_name load_ref default_ref
  while IFS=$'\t' read -r tar_name load_ref default_ref; do
    [[ -n "${tar_name}" ]] || continue
    resolve_target_ref "${default_ref}"
    return 0
  done < "${IMAGE_INDEX}"
  return 1
}

ensure_auth_secret() {
  if kubectl get secret "${AUTH_SECRET}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    ok "Using existing credential Secret ${NAMESPACE}/${AUTH_SECRET}; credentials were not rotated"
    return 0
  fi

  if [[ "${ROOT_PASSWORD_EXPLICIT}" != "true" ]]; then
    ROOT_PASSWORD="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
  fi
  [[ ${#ROOT_PASSWORD} -ge 16 ]] || die "root password must be at least 16 characters"

  local secret_dir="${WORKDIR}/secret"
  mkdir -p "${secret_dir}"
  chmod 700 "${secret_dir}"
  printf '%s' "${ROOT_USER}" > "${secret_dir}/rootUser"
  printf '%s' "${ROOT_PASSWORD}" > "${secret_dir}/rootPassword"
  chmod 600 "${secret_dir}/rootUser" "${secret_dir}/rootPassword"

  kubectl create secret generic "${AUTH_SECRET}" \
    -n "${NAMESPACE}" \
    --from-file=rootUser="${secret_dir}/rootUser" \
    --from-file=rootPassword="${secret_dir}/rootPassword" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  ok "Created credential Secret ${NAMESPACE}/${AUTH_SECRET}"
  if [[ "${ROOT_PASSWORD_EXPLICIT}" != "true" ]]; then
    printf '\nGenerated credentials (store them securely now):\n'
    printf '  user: %s\n' "${ROOT_USER}"
    printf '  password: %s\n\n' "${ROOT_PASSWORD}"
  fi
}

install_release() {
  kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}" >/dev/null
  ensure_auth_secret

  if [[ "${ENABLE_SERVICEMONITOR}" == "true" ]] && ! kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    warn "ServiceMonitor CRD not found; disabling ServiceMonitor"
    ENABLE_SERVICEMONITOR="false"
  fi
  if [[ "${ENABLE_PROMETHEUSRULE}" == "true" ]] && ! kubectl get crd prometheusrules.monitoring.coreos.com >/dev/null 2>&1; then
    warn "PrometheusRule CRD not found; disabling PrometheusRule"
    ENABLE_PROMETHEUSRULE="false"
  fi

  local image_ref image_repo image_tag
  image_ref="$(find_target_image)" || die "unable to resolve SILO image"
  image_repo="${image_ref%:*}"
  image_tag="${image_ref##*:}"

  local cmd=(
    helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}"
    -n "${NAMESPACE}" --create-namespace --wait --timeout "${WAIT_TIMEOUT}"
    --set-string "fullnameOverride=${RELEASE_NAME}"
    --set-string "mode=${MODE}"
    --set "replicas=${REPLICAS}"
    --set "drivesPerNode=${DRIVES_PER_NODE}"
    --set-string "auth.existingSecret=${AUTH_SECRET}"
    --set-string "persistence.storageClass=${STORAGE_CLASS}"
    --set-string "persistence.size=${STORAGE_SIZE}"
    --set-string "service.type=${SERVICE_TYPE}"
    --set-string "console.service.type=${CONSOLE_SERVICE_TYPE}"
    --set "console.enabled=${CONSOLE_ENABLED}"
    --set-string "image.repository=${image_repo}"
    --set-string "image.tag=${image_tag}"
    --set-string "image.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "resources.requests.cpu=${REQUEST_CPU}"
    --set-string "resources.requests.memory=${REQUEST_MEM}"
    --set-string "resources.limits.cpu=${LIMIT_CPU}"
    --set-string "resources.limits.memory=${LIMIT_MEM}"
    --set "metrics.serviceMonitor.enabled=${ENABLE_SERVICEMONITOR}"
    --set "metrics.prometheusRule.enabled=${ENABLE_PROMETHEUSRULE}"
    --set "metrics.dashboards.enabled=${ENABLE_DASHBOARD}"
    --set "networkPolicy.enabled=${NETWORK_POLICY_ENABLED}"
    --set "tls.enabled=${TLS_ENABLED}"
  )

  [[ "${SERVICE_TYPE}" == "NodePort" ]] && cmd+=(--set "service.nodePort=${API_NODE_PORT}")
  [[ "${CONSOLE_ENABLED}" == "true" && "${CONSOLE_SERVICE_TYPE}" == "NodePort" ]] && cmd+=(--set "console.service.nodePort=${CONSOLE_NODE_PORT}")
  [[ "${TLS_ENABLED}" == "true" ]] && cmd+=(--set-string "tls.existingSecret=${TLS_SECRET}")

  log "Installing SILO ${image_tag}; credentials are intentionally omitted from the Helm command"
  "${cmd[@]}"
}

show_credentials() {
  kubectl get secret "${AUTH_SECRET}" -n "${NAMESPACE}" >/dev/null 2>&1 || die "Secret ${NAMESPACE}/${AUTH_SECRET} not found"
  local user_b64 pass_b64 user pass
  user_b64="$(kubectl get secret "${AUTH_SECRET}" -n "${NAMESPACE}" -o jsonpath='{.data.rootUser}')"
  pass_b64="$(kubectl get secret "${AUTH_SECRET}" -n "${NAMESPACE}" -o jsonpath='{.data.rootPassword}')"
  user="$(printf '%s' "${user_b64}" | base64 --decode)"
  pass="$(printf '%s' "${pass_b64}" | base64 --decode)"
  printf 'SILO credentials (%s/%s):\n' "${NAMESPACE}" "${AUTH_SECRET}"
  printf '  user: %s\n' "${user}"
  printf '  password: %s\n' "${pass}"
}

show_endpoint() {
  local api_svc="${RELEASE_NAME}"
  local console_svc="${RELEASE_NAME}-console"
  local api_type api_port api_node_port api_port_name scheme node_ip
  api_type="$(kubectl get svc "${api_svc}" -n "${NAMESPACE}" -o jsonpath='{.spec.type}' 2>/dev/null || true)"
  [[ -n "${api_type}" ]] || die "Service ${NAMESPACE}/${api_svc} not found"
  api_port="$(kubectl get svc "${api_svc}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].port}')"
  api_node_port="$(kubectl get svc "${api_svc}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}')"
  api_port_name="$(kubectl get svc "${api_svc}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].name}')"
  scheme="http"
  [[ "${api_port_name}" == "https" ]] && scheme="https"

  printf 'S3 cluster endpoint:\n'
  printf '  %s://%s.%s.svc.cluster.local:%s\n' "${scheme}" "${api_svc}" "${NAMESPACE}" "${api_port}"

  if [[ "${api_type}" == "NodePort" && -n "${api_node_port}" ]]; then
    node_ip="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"
    printf 'S3 NodePort:\n'
    printf '  %s://%s:%s\n' "${scheme}" "${node_ip:-<NODE_IP>}" "${api_node_port}"
  fi

  if kubectl get svc "${console_svc}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    local console_type console_port console_node_port console_port_name console_scheme
    console_type="$(kubectl get svc "${console_svc}" -n "${NAMESPACE}" -o jsonpath='{.spec.type}')"
    console_port="$(kubectl get svc "${console_svc}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].port}')"
    console_node_port="$(kubectl get svc "${console_svc}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}')"
    console_port_name="$(kubectl get svc "${console_svc}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].name}')"
    console_scheme="http"
    [[ "${console_port_name}" == "https-console" ]] && console_scheme="https"
    printf 'Console cluster endpoint:\n'
    printf '  %s://%s.%s.svc.cluster.local:%s\n' "${console_scheme}" "${console_svc}" "${NAMESPACE}" "${console_port}"
    if [[ "${console_type}" == "NodePort" && -n "${console_node_port}" ]]; then
      [[ -n "${node_ip:-}" ]] || node_ip="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"
      printf 'Console NodePort:\n'
      printf '  %s://%s:%s\n' "${console_scheme}" "${node_ip:-<NODE_IP>}" "${console_node_port}"
    fi
  fi
}

show_status() {
  helm status "${RELEASE_NAME}" -n "${NAMESPACE}" || true
  kubectl get pods,svc,pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true
  kubectl get configmap -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME},grafana_dashboard=1" || true
  if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    kubectl get servicemonitor -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true
  fi
  if kubectl get crd prometheusrules.monitoring.coreos.com >/dev/null 2>&1; then
    kubectl get prometheusrule -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true
  fi
}

confirm() {
  [[ "${AUTO_YES}" == "true" ]] && return
  printf 'Action=%s namespace=%s release=%s mode=%s replicas=%s storage=%s/%s service=%s:%s console=%s:%s\n' \
    "${ACTION}" "${NAMESPACE}" "${RELEASE_NAME}" "${MODE}" "${REPLICAS}" "${STORAGE_CLASS}" "${STORAGE_SIZE}" \
    "${SERVICE_TYPE}" "${API_NODE_PORT}" "${CONSOLE_SERVICE_TYPE}" "${CONSOLE_NODE_PORT}"
  read -r -p "Continue? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || die "cancelled"
}

main() {
  parse_args "$@"
  validate
  apply_profile
  case "${ACTION}" in
    help) usage ;;
    install)
      check_deps
      confirm
      extract_payload
      prepare_images
      install_release
      show_status
      show_endpoint
      printf '\nRun "%s credentials -n %s --release-name %s" to display the Console/S3 root credentials.\n' \
        "$(basename "$0")" "${NAMESPACE}" "${RELEASE_NAME}"
      ;;
    status)
      check_deps
      show_status
      show_endpoint || true
      ;;
    credentials)
      check_deps
      show_credentials
      ;;
    endpoint)
      check_deps
      show_endpoint
      ;;
    uninstall)
      check_deps
      confirm
      helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}"
      warn "PVCs and credential Secrets are intentionally retained"
      ;;
    *) die "unsupported action: ${ACTION}" ;;
  esac
}

main "$@"
exit 0

__PAYLOAD_BELOW__
