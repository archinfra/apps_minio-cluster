# SILO 0.2.1

Archinfra object-storage delivery release focused on operational visibility and
private-delivery usability.

## Changes from 0.2.0

- S3 API defaults to NodePort `30093`.
- Web Console defaults to NodePort `30092`.
- Root user remains `silo-admin`.
- Password is generated on first install and stored in `silo-root-credentials`.
- New installer actions: `credentials` and `endpoint`.
- ServiceMonitor moves to Metrics V3: `/minio/metrics/v3`.
- Adds Grafana Dashboard: `SILO Object Storage Overview`.
- Expands Prometheus rules for target loss, node/drive loss, erasure health, capacity, stale usage data and S3 errors.
- CI asserts NodePorts, V3 endpoint, Dashboard and key alert rules.
- Legacy MinIO workflow is restricted to legacy paths so SILO-only changes no longer rebuild the old MinIO installer.

## Security note

NodePort is enabled by default for customer delivery convenience. This increases network exposure compared with 0.2.0. Production deployments must restrict NodePort reachability and should enable TLS when crossing untrusted networks.

Credentials remain Secret-backed and are never added to Helm command-line arguments.
