# PGSTY SILO delivery baseline

## Decision

New object-storage deliveries use PGSTY SILO as the maintained MinIO-compatible backend. The legacy Bitnami MinIO path remains only for rollback and controlled migration work.

Archinfra release `0.2.1` pins:

- Upstream project: `pgsty/silo`
- Upstream base release: `RELEASE.2026-09-03T13-18-01Z`
- Security-fixed source commit: `1233254309b15571f101b2b26d531951ceaeef1e`
- Security advisory: `SN-2026-011`
- Architectures: `linux/amd64`, `linux/arm64`
- Default topology: 4-node distributed
- S3 NodePort: `30093`
- Console NodePort: `30092`
- Default user: `silo-admin`
- Password: generated at install time and stored in Kubernetes Secret
- Monitoring: Metrics V3 + ServiceMonitor + PrometheusRule + Grafana Dashboard

## Authentication contract

The Server and Console use `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`. The installer reuses an existing `silo-root-credentials` Secret; otherwise it creates `silo-admin` and a 24-byte random password encoded as 48 hex characters. Passwords are not passed through Helm argv.

## Exposure contract

0.2.1 defaults S3 and Console to NodePort for private-delivery operability: API `9000 -> 30093`, Console `9001 -> 30092`. Production environments must restrict reachability with firewalls, ACLs, security groups, NetworkPolicy or gateways. Enable TLS across untrusted networks.

## Monitoring contract

The maintained scrape endpoint is `/minio/metrics/v3`.

V3 semantics:

- cluster-scoped groups are duplicated by every scraped node; aggregate cluster state with `max()` / `min()`, not `sum()`;
- zero values may be omitted; use zero-guards where a legitimate zero is meaningful;
- API metric labels use `name` instead of the old V2 `api` label;
- durations use seconds.

Default monitoring objects are ServiceMonitor, PrometheusRule and a Grafana ConfigMap labeled `grafana_dashboard=1`.

Alert coverage includes scrape loss, node/drive loss, erasure health, capacity warning/critical, stale usage data and S3 error conditions.

## MinIO compatibility contract

SILO preserves S3 API, `MINIO_*`, `minio_*`, `/minio/*` and `.minio.sys` compatibility. The classic image includes `mcli` and the legacy `mc` alias.

## Migration boundary

Do not directly Helm-upgrade the legacy Bitnami StatefulSet to the SILO chart. Protect data with a recoverable snapshot/copy and perform a controlled cutover. Never mix MinIO and SILO nodes inside one erasure set.

## Production acceptance gate

Validate `mc cp`/`mirror`, PUT/GET/DELETE/multipart, presigned URLs, IAM, versioning/lifecycle, Prometheus target discovery, V3 Dashboard population, alert evaluation, quorum, node loss/recovery and rollback.

## AGPL delivery note

SILO server, Console and MCLI are AGPL-3.0-or-later. Preserve license/attribution and corresponding-source information with the delivery BOM.
