# SILO 0.2.1 Release Notes

Archinfra SILO `0.2.1` is an operations and observability update on top of the `0.2.0` security-patched source baseline.

## Server baseline

The server source does not change in this release:

- Upstream: `pgsty/silo`
- Base release: `RELEASE.2026-09-03T13-18-01Z`
- Fixed source commit: `1233254309b15571f101b2b26d531951ceaeef1e`
- Security boundary: includes `SN-2026-011` fix
- Image tag: `2026.09.03-sn011.123325430`

## What changed

### Default access

- S3 API defaults to NodePort `30093`.
- Web Console defaults to NodePort `30092`.
- Both may be changed to ClusterIP/LoadBalancer from installer flags.
- Installer warns when externally exposed without TLS.

### Authentication

- Default root/Console username: `silo-admin`.
- Password is randomly generated on first installation unless explicitly supplied.
- Credentials are stored in Kubernetes Secret `silo-root-credentials`.
- Existing Secrets are reused without automatic rotation.
- Root password is never passed in Helm argv.
- New installer actions:
  - `endpoint`
  - `credentials`

### Monitoring

- ServiceMonitor migrated from Metrics V2 to `/minio/metrics/v3`.
- Added `SILO Cluster Overview` Grafana dashboard ConfigMap.
- Added production-oriented Prometheus rules:
  - `SiloMetricsAbsent`
  - `SiloTargetDown`
  - `SiloNodeOffline`
  - `SiloDriveOffline`
  - `SiloErasureSetUnhealthy`
  - `SiloCapacityLow`
  - `SiloCapacityCritical`
  - `SiloUsageDataStale`
  - `SiloS3ErrorRateHigh`
- V3 expressions account for duplicate cluster-scoped samples and omitted zero values.

### Operations

`status` now includes the monitoring resources and dashboard ConfigMap. `endpoint` reports cluster and NodePort endpoints. `credentials` retrieves the existing root credential Secret for a controlled operator terminal.

### Build and CI

CI now verifies that Helm rendering contains:

- S3 NodePort `30093`;
- Console NodePort `30092`;
- `/minio/metrics/v3`;
- Grafana dashboard discovery labels and dashboard title;
- critical V3 metrics and alert rules;
- no legacy `/minio/v2/metrics/node` ServiceMonitor endpoint.

The existing amd64/arm64 pinned-source build, `silo`, `mc`, `mc cp` and installer checksum gates remain mandatory.

## Compatibility

S3 API and `mc/mcli` compatibility are unchanged. This release does not alter object data layout and does not change the migration rule: do not directly Helm-upgrade a legacy Bitnami MinIO StatefulSet to this chart, and do not mix MinIO and SILO nodes in one erasure set.

## Production note

Default NodePort exposure is intentionally optimized for private delivery usability. Deployments on less trusted networks should enable TLS and appropriate firewall/NetworkPolicy controls, or override both services to ClusterIP and publish them through the platform gateway.
