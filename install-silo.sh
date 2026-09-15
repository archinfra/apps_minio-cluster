#!/usr/bin/env bash
set -Eeuo pipefail
APP_NAME="silo-cluster"; APP_VERSION="0.2.1"; WORKDIR="/tmp/${APP_NAME}-installer"
CHART_DIR="${WORKDIR}/charts/silo"; IMAGE_INDEX="${WORKDIR}/images/image-index.tsv"
ACTION="help"; RELEASE_NAME="silo"; NAMESPACE="aict"; MODE="distributed"; REPLICAS="4"; DRIVES_PER_NODE="1"
STORAGE_CLASS="nfs"; STORAGE_SIZE="500Gi"; SERVICE_TYPE="NodePort"; API_NODE_PORT="30093"
CONSOLE_ENABLED="true"; CONSOLE_SERVICE_TYPE="NodePort"; CONSOLE_NODE_PORT="30092"
AUTH_SECRET="silo-root-credentials"; ROOT_USER="silo-admin"; ROOT_PASSWORD=""; ROOT_PASSWORD_EXPLICIT="false"
TLS_ENABLED="false"; TLS_SECRET=""; RESOURCE_PROFILE="mid"; ENABLE_SERVICEMONITOR="true"; ENABLE_PROMETHEUSRULE="true"; ENABLE_DASHBOARD="true"
NETWORK_POLICY_ENABLED="false"; REGISTRY_REPO="sealos.hub:5000/kube4"; REGISTRY_REPO_EXPLICIT="false"; REGISTRY_USER="admin"; REGISTRY_PASS="passw0rd"
IMAGE_PULL_POLICY="IfNotPresent"; SKIP_IMAGE_PREPARE="false"; WAIT_TIMEOUT="15m"; AUTO_YES="false"
REQUEST_CPU="500m"; REQUEST_MEM="1Gi"; LIMIT_CPU="4"; LIMIT_MEM="8Gi"
log(){ printf '\033[0;36m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }; warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }; die(){ printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
cleanup(){ rm -rf "${WORKDIR}"; }; trap cleanup EXIT
usage(){ cat <<EOF2
SILO Cluster Offline Installer ${APP_VERSION}
Usage: ./$(basename "$0") <install|status|endpoint|credentials|uninstall|help> [options]
Defaults: namespace=${NAMESPACE}, release=${RELEASE_NAME}, S3 NodePort=${API_NODE_PORT}, Console NodePort=${CONSOLE_NODE_PORT}, user=${ROOT_USER}
Core: -n|--namespace <ns> --release-name <name> --mode <standalone|distributed> --replicas <n> --drives-per-node <n>
      --storage-class <name> --storage-size <size> --resource-profile <low|mid|high>
Credentials: --auth-secret <name> --root-user <user> --root-password <password>; credentials prints current Secret values
Exposure: --service-type <ClusterIP|NodePort|LoadBalancer> --api-node-port <port>
          --console-service-type <ClusterIP|NodePort|LoadBalancer> --console-node-port <port> --disable-console
Security: --enable-tls --tls-secret <name> --enable-network-policy
Monitoring: --disable-servicemonitor --disable-prometheusrule --disable-dashboard
Images: --registry <repo-prefix> --registry-user <user> --registry-password <password> --image-pull-policy <policy> --skip-image-prepare
Other: --wait-timeout <duration> -y|--yes
Examples:
  ./$(basename "$0") install -y
  ./$(basename "$0") endpoint -n aict
  ./$(basename "$0") credentials -n aict
EOF2
}
needarg(){ [[ $# -ge 2 ]] || die "missing value for $1"; }
parse_args(){
  [[ $# -gt 0 ]] || return 0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|status|endpoint|credentials|uninstall|help) ACTION="$1"; shift;;
      -n|--namespace) needarg "$@"; NAMESPACE="$2"; shift 2;; --release-name) needarg "$@"; RELEASE_NAME="$2"; shift 2;;
      --mode) needarg "$@"; MODE="$2"; shift 2;; --replicas) needarg "$@"; REPLICAS="$2"; shift 2;; --drives-per-node) needarg "$@"; DRIVES_PER_NODE="$2"; shift 2;;
      --storage-class) needarg "$@"; STORAGE_CLASS="$2"; shift 2;; --storage-size) needarg "$@"; STORAGE_SIZE="$2"; shift 2;; --resource-profile) needarg "$@"; RESOURCE_PROFILE="$2"; shift 2;;
      --auth-secret) needarg "$@"; AUTH_SECRET="$2"; shift 2;; --root-user) needarg "$@"; ROOT_USER="$2"; shift 2;; --root-password) needarg "$@"; ROOT_PASSWORD="$2"; ROOT_PASSWORD_EXPLICIT="true"; shift 2;;
      --service-type) needarg "$@"; SERVICE_TYPE="$2"; shift 2;; --api-node-port) needarg "$@"; API_NODE_PORT="$2"; shift 2;;
      --console-service-type) needarg "$@"; CONSOLE_SERVICE_TYPE="$2"; shift 2;; --console-node-port) needarg "$@"; CONSOLE_NODE_PORT="$2"; shift 2;; --disable-console) CONSOLE_ENABLED="false"; shift;;
      --enable-tls) TLS_ENABLED="true"; shift;; --tls-secret) needarg "$@"; TLS_SECRET="$2"; shift 2;; --enable-network-policy) NETWORK_POLICY_ENABLED="true"; shift;;
      --disable-servicemonitor) ENABLE_SERVICEMONITOR="false"; shift;; --disable-prometheusrule) ENABLE_PROMETHEUSRULE="false"; shift;; --disable-dashboard) ENABLE_DASHBOARD="false"; shift;;
      --registry) needarg "$@"; REGISTRY_REPO="$2"; REGISTRY_REPO_EXPLICIT="true"; shift 2;; --registry-user) needarg "$@"; REGISTRY_USER="$2"; shift 2;; --registry-password) needarg "$@"; REGISTRY_PASS="$2"; shift 2;;
      --image-pull-policy) needarg "$@"; IMAGE_PULL_POLICY="$2"; shift 2;; --skip-image-prepare) SKIP_IMAGE_PREPARE="true"; shift;; --wait-timeout) needarg "$@"; WAIT_TIMEOUT="$2"; shift 2;;
      -y|--yes) AUTO_YES="true"; shift;; -h|--help) ACTION="help"; shift;; *) die "unknown argument: $1";;
    esac
  done
}
validate_np(){ [[ "$2" =~ ^[0-9]+$ ]] && (( $2>=30000 && $2<=32767 )) || die "$1 must be in 30000-32767"; }
validate(){
  case "$MODE" in standalone|distributed);; *) die "unsupported mode: $MODE";; esac
  case "$SERVICE_TYPE" in ClusterIP|NodePort|LoadBalancer);; *) die "unsupported service type";; esac
  case "$CONSOLE_SERVICE_TYPE" in ClusterIP|NodePort|LoadBalancer);; *) die "unsupported console service type";; esac
  case "$IMAGE_PULL_POLICY" in Always|IfNotPresent|Never);; *) die "unsupported image pull policy";; esac
  [[ "$REPLICAS" =~ ^[0-9]+$ && "$DRIVES_PER_NODE" =~ ^[0-9]+$ ]] || die "replicas/drives must be integers"
  [[ "$MODE" != distributed ]] || (( REPLICAS>=4 )) || die "distributed mode requires >=4 replicas"; [[ "$MODE" != standalone ]] || REPLICAS=1
  [[ "$SERVICE_TYPE" != NodePort ]] || validate_np api-node-port "$API_NODE_PORT"; [[ "$CONSOLE_SERVICE_TYPE" != NodePort ]] || validate_np console-node-port "$CONSOLE_NODE_PORT"
  [[ "$ACTION" != install || "$TLS_ENABLED" != true || -n "$TLS_SECRET" ]] || die "--tls-secret is required with --enable-tls"
  [[ "$ACTION" != install || ( "$SERVICE_TYPE" == ClusterIP && "$CONSOLE_SERVICE_TYPE" == ClusterIP ) || "$TLS_ENABLED" == true ]] || warn "NodePort exposure is enabled without TLS; keep it on a trusted private network or enable TLS"
}
profile(){ case "${RESOURCE_PROFILE,,}" in low) REQUEST_CPU=250m; REQUEST_MEM=512Mi; LIMIT_CPU=2; LIMIT_MEM=4Gi;; mid|midd|medium) RESOURCE_PROFILE=mid;; high) REQUEST_CPU=1; REQUEST_MEM=2Gi; LIMIT_CPU=8; LIMIT_MEM=16Gi;; *) die "unsupported resource profile";; esac; }
need(){ command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }
check_deps(){ need kubectl; case "$ACTION" in install) need helm; need tar; need od; [[ "$SKIP_IMAGE_PREPARE" == true ]] || need docker;; status|uninstall) need helm;; credentials) need base64;; esac; }
payload_offset(){ local l o s=0 h; l="$(awk '/^__PAYLOAD_BELOW__$/ {print NR; exit}' "$0")"; [[ -n "$l" ]] || die "payload marker not found"; o=$(( $(head -n "$l" "$0"|wc -c|tr -d ' ')+1 )); while :; do h="$(dd if="$0" bs=1 skip="$((o+s-1))" count=1 2>/dev/null|od -An -tx1|tr -d ' \n')"; case "$h" in 0a|0d) s=$((s+1));; "") die "invalid payload boundary";; *) break;; esac; done; printf '%s' "$((o+s))"; }
extract_payload(){ rm -rf "$WORKDIR"; mkdir -p "$WORKDIR"; tail -c +"$(payload_offset)" "$0"|tar -xz -C "$WORKDIR"; [[ -d "$CHART_DIR" && -f "$IMAGE_INDEX" ]] || die "payload incomplete"; }
resolve_ref(){ [[ "$REGISTRY_REPO_EXPLICIT" == true ]] && printf '%s/%s\n' "$REGISTRY_REPO" "${1##*/}" || printf '%s\n' "$1"; }
prepare_images(){ [[ "$SKIP_IMAGE_PREPARE" == true ]] && return; local host="${REGISTRY_REPO%%/*}" t l d r; printf '%s' "$REGISTRY_PASS"|docker login "$host" -u "$REGISTRY_USER" --password-stdin >/dev/null; while IFS=$'\t' read -r t l d; do [[ -n "$t" ]] || continue; r="$(resolve_ref "$d")"; docker load -i "$WORKDIR/images/$t" >/dev/null; [[ "$l" == "$r" ]] || docker tag "$l" "$r"; docker push "$r" >/dev/null; done < "$IMAGE_INDEX"; }
find_image(){ local t l d; while IFS=$'\t' read -r t l d; do [[ -n "$t" ]] || continue; resolve_ref "$d"; return; done < "$IMAGE_INDEX"; return 1; }
secret_value(){ kubectl get secret "$AUTH_SECRET" -n "$NAMESPACE" -o "jsonpath={.data.$1}" 2>/dev/null|base64 -d; }
ensure_secret(){
  if kubectl get secret "$AUTH_SECRET" -n "$NAMESPACE" >/dev/null 2>&1; then ok "Using existing Secret $NAMESPACE/$AUTH_SECRET; credentials were not rotated"; return; fi
  [[ "$ROOT_PASSWORD_EXPLICIT" == true ]] || ROOT_PASSWORD="$(od -An -N24 -tx1 /dev/urandom|tr -d ' \n')"; [[ ${#ROOT_PASSWORD} -ge 16 ]] || die "root password must be >=16 chars"
  local d="$WORKDIR/secret"; mkdir -p "$d"; chmod 700 "$d"; printf '%s' "$ROOT_USER">"$d/rootUser"; printf '%s' "$ROOT_PASSWORD">"$d/rootPassword"; chmod 600 "$d"/*
  kubectl create secret generic "$AUTH_SECRET" -n "$NAMESPACE" --from-file=rootUser="$d/rootUser" --from-file=rootPassword="$d/rootPassword" --dry-run=client -o yaml|kubectl apply -f - >/dev/null
  ok "Created Secret $NAMESPACE/$AUTH_SECRET"; [[ "$ROOT_PASSWORD_EXPLICIT" == true ]] || printf '\nGenerated credentials:\n  user: %s\n  password: %s\n\n' "$ROOT_USER" "$ROOT_PASSWORD"
}
show_credentials(){ kubectl get secret "$AUTH_SECRET" -n "$NAMESPACE" >/dev/null 2>&1 || die "Secret $NAMESPACE/$AUTH_SECRET not found"; printf 'SILO Console / S3 credentials\n  Secret: %s\n  Username: %s\n  Password: %s\n' "$AUTH_SECRET" "$(secret_value rootUser)" "$(secret_value rootPassword)"; warn "credentials were printed to stdout"; }
node_ip(){ kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'|head -n1; }
show_endpoints(){
  local a="$RELEASE_NAME" c="$RELEASE_NAME-console" ip t p n scheme=http; kubectl get svc "$a" -n "$NAMESPACE" >/dev/null 2>&1 || die "Service $NAMESPACE/$a not found"
  [[ "$(kubectl get svc "$a" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].name}')" != https* ]] || scheme=https
  p="$(kubectl get svc "$a" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')"; t="$(kubectl get svc "$a" -n "$NAMESPACE" -o jsonpath='{.spec.type}')"; printf 'SILO endpoints\n  S3 cluster: %s://%s.%s.svc.cluster.local:%s\n' "$scheme" "$a" "$NAMESPACE" "$p"
  if [[ "$t" == NodePort ]]; then ip="$(node_ip)"; n="$(kubectl get svc "$a" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')"; printf '  S3 NodePort: %s://%s:%s\n' "$scheme" "${ip:-<NODE_IP>}" "$n"; fi
  if kubectl get svc "$c" -n "$NAMESPACE" >/dev/null 2>&1; then p="$(kubectl get svc "$c" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')"; t="$(kubectl get svc "$c" -n "$NAMESPACE" -o jsonpath='{.spec.type}')"; printf '  Console cluster: %s://%s.%s.svc.cluster.local:%s\n' "$scheme" "$c" "$NAMESPACE" "$p"; if [[ "$t" == NodePort ]]; then [[ -n "${ip:-}" ]] || ip="$(node_ip)"; n="$(kubectl get svc "$c" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')"; printf '  Console NodePort: %s://%s:%s\n' "$scheme" "${ip:-<NODE_IP>}" "$n"; fi; fi
  printf '  Console user: %s\n  Password: run "%s credentials -n %s"\n' "$(secret_value rootUser 2>/dev/null || printf '%s' "$ROOT_USER")" "$(basename "$0")" "$NAMESPACE"
}
install_release(){
  kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE" >/dev/null; ensure_secret
  [[ "$ENABLE_SERVICEMONITOR" != true || $(kubectl get crd servicemonitors.monitoring.coreos.com --ignore-not-found -o name) ]] || { warn "ServiceMonitor CRD missing; disabling"; ENABLE_SERVICEMONITOR=false; }
  [[ "$ENABLE_PROMETHEUSRULE" != true || $(kubectl get crd prometheusrules.monitoring.coreos.com --ignore-not-found -o name) ]] || { warn "PrometheusRule CRD missing; disabling"; ENABLE_PROMETHEUSRULE=false; }
  local ref repo tag; ref="$(find_image)" || die "unable to resolve image"; repo="${ref%:*}"; tag="${ref##*:}"
  local cmd=(helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" -n "$NAMESPACE" --create-namespace --wait --timeout "$WAIT_TIMEOUT"
    --set-string "fullnameOverride=$RELEASE_NAME" --set-string "mode=$MODE" --set "replicas=$REPLICAS" --set "drivesPerNode=$DRIVES_PER_NODE" --set-string "auth.existingSecret=$AUTH_SECRET"
    --set-string "persistence.storageClass=$STORAGE_CLASS" --set-string "persistence.size=$STORAGE_SIZE" --set-string "service.type=$SERVICE_TYPE" --set-string "console.service.type=$CONSOLE_SERVICE_TYPE" --set "console.enabled=$CONSOLE_ENABLED"
    --set-string "image.repository=$repo" --set-string "image.tag=$tag" --set-string "image.pullPolicy=$IMAGE_PULL_POLICY" --set-string "resources.requests.cpu=$REQUEST_CPU" --set-string "resources.requests.memory=$REQUEST_MEM" --set-string "resources.limits.cpu=$LIMIT_CPU" --set-string "resources.limits.memory=$LIMIT_MEM"
    --set "metrics.serviceMonitor.enabled=$ENABLE_SERVICEMONITOR" --set "metrics.prometheusRule.enabled=$ENABLE_PROMETHEUSRULE" --set "metrics.dashboards.enabled=$ENABLE_DASHBOARD" --set "networkPolicy.enabled=$NETWORK_POLICY_ENABLED" --set "tls.enabled=$TLS_ENABLED")
  [[ "$SERVICE_TYPE" == NodePort ]] && cmd+=(--set "service.nodePort=$API_NODE_PORT"); [[ "$CONSOLE_ENABLED" == true && "$CONSOLE_SERVICE_TYPE" == NodePort ]] && cmd+=(--set "console.service.nodePort=$CONSOLE_NODE_PORT"); [[ "$TLS_ENABLED" == true ]] && cmd+=(--set-string "tls.existingSecret=$TLS_SECRET")
  log "Installing SILO $tag; credentials are omitted from Helm argv"; "${cmd[@]}"
}
show_status(){ helm status "$RELEASE_NAME" -n "$NAMESPACE" || true; kubectl get pods,svc -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" || true; kubectl get pvc -n "$NAMESPACE" || true; kubectl get servicemonitor "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || true; kubectl get prometheusrule "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || true; kubectl get cm "$RELEASE_NAME-dashboard" -n "$NAMESPACE" 2>/dev/null || true; }
confirm(){ [[ "$AUTO_YES" == true ]] && return; printf 'Action=%s namespace=%s release=%s mode=%s replicas=%s storage=%s/%s service=%s console=%s\n' "$ACTION" "$NAMESPACE" "$RELEASE_NAME" "$MODE" "$REPLICAS" "$STORAGE_CLASS" "$STORAGE_SIZE" "$SERVICE_TYPE" "$CONSOLE_SERVICE_TYPE"; read -r -p 'Continue? [y/N] ' a; [[ "$a" =~ ^[Yy]$ ]] || die cancelled; }
main(){ parse_args "$@"; validate; profile; case "$ACTION" in help) usage;; install) check_deps; confirm; extract_payload; prepare_images; install_release; show_status; show_endpoints;; status) check_deps; show_status; show_endpoints||true;; endpoint) check_deps; show_endpoints;; credentials) check_deps; show_credentials;; uninstall) check_deps; confirm; helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"; warn "PVCs and credential Secret are retained";; *) die "unsupported action";; esac; }
main "$@"
exit 0
__PAYLOAD_BELOW__
