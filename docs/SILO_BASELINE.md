# PGSTY SILO delivery baseline

## Decision

New object-storage deliveries use PGSTY SILO as the maintained MinIO-compatible backend. The legacy Bitnami MinIO path remains only for rollback and controlled migration work.

Archinfra release `0.2.1` pins:

- Upstream project: `pgsty/silo`
- Upstream base release: `RELEASE.2026-09-03T13-18-01Z`
- Security-fixed source commit: `1233254309b15571f101b2b26d531951ceaeef1e`
- Security advisory addressed by the source pin: `SN-2026-011`
- Archinfra image tag: `2026.09.03-sn011.123325430`
- License: `AGPL-3.0-or-later`
- Architectures: `linux/amd64`, `linux/arm64`
- Default topology: 4-node distributed, 1 drive per node
- Default S3 NodePort: `30093`
- Default Console NodePort: `30092`
- Default root/Console user: `silo-admin`
- Default password: randomly generated on first install and stored in Kubernetes Secret `silo-root-credentials`
- Default monitoring: Metrics V3 + ServiceMonitor + PrometheusRule + Grafana Dashboard
- Offline installer runtime: no `jq` dependency

## Security release boundary

As of 2026-09-15, SILO's published Server release `RELEASE.2026-09-03T13-18-01Z` is affected by `SN-2026-011`; the fix starts at source commit `1233254309b15571f101b2b26d531951ceaeef1e`.

Archinfra therefore does not redistribute that vulnerable published Server image. The build pipeline fetches the exact fixed source commit, verifies the Git SHA, builds the classic SILO container for the requested architecture, and packages that locally built image into the offline installer.

This remains an Archinfra security-patched source build rather than an upstream release. When a later upstream release explicitly includes the fix, the baseline can return to an upstream release after compatibility and regression testing.

## Authentication and access

The same root credential protects the S3 administrative identity and SILO Web Console login.

- Secret: `silo-root-credentials`
- key `rootUser`: default `silo-admin`
- key `rootPassword`: randomly generated strong password unless explicitly supplied
- rerunning installation never rotates an existing Secret
- credentials never appear in Helm command-line arguments

Operational commands:

```bash
./silo-cluster-installer-0.2.1-amd64.run endpoint -n aict
./silo-cluster-installer-0.2.1-amd64.run credentials -n aict
```

`credentials` deliberately prints the Secret value and emits a warning; use it only in a controlled operator terminal.

For private-delivery convenience, S3 and Console default to NodePort `30093` and `30092`. The installer warns when NodePort or LoadBalancer exposure is enabled without TLS. Environments with a broader trust boundary should configure TLS or change both services back to ClusterIP and expose them through the platform gateway/Ingress.

## MinIO compatibility contract

SILO preserves the MinIO-facing compatibility contract: S3 API, `MINIO_*` variables, `minio_*` metric prefix, `/minio/*` routes and `.minio.sys` disk format.

The classic SILO image ships `mcli` with the legacy `mc` compatibility alias. Existing automation remains an acceptance target:

```bash
mc alias set storage http://silo:9000 ACCESS_KEY SECRET_KEY
mc cp backup.tar storage/backups/
mc mirror ./directory storage/bucket/path/
mc ls storage/bucket/
mc stat storage/bucket/backup.tar
```

Run `scripts/silo-mc-smoke.sh` after installation to exercise real upload, download, stat and mirror behavior.

## Monitoring baseline

### Metrics endpoint

Archinfra `0.2.1` standardizes on SILO/MinIO Metrics V3:

```text
/minio/metrics/v3
```

Metrics are exposed directly by SILO; there is no separate exporter image. The StatefulSet sets public Prometheus metric access for the monitoring endpoint.

V3 differs materially from V2:

- cluster-level metric groups are exported by every node, so cluster values use `max()`/`min()` instead of summing duplicate copies;
- valid zero values may be omitted by the server, so dashboard and alert expressions use companion-series zero guards where appropriate;
- API metrics use the `name` label and node metrics use `server`;
- duration values are seconds.

### ServiceMonitor

The chart creates a ServiceMonitor by default when the CRD is available. It selects the S3 service and scrapes `/minio/metrics/v3` every 30 seconds. Discovery label:

```yaml
monitoring.archinfra.io/stack: default
```

### Grafana Dashboard

The chart creates a `silo-dashboard` ConfigMap with `grafana_dashboard: "1"` so the standard Grafana sidecar can discover it.

`SILO Cluster Overview` includes:

- scrape target state;
- online/offline nodes;
- online/offline drives;
- erasure-set health;
- usable/free capacity and free percentage;
- bucket/object counts;
- S3 request/error rate;
- S3 ingress/egress;
- internode traffic;
- process CPU/memory;
- drive usage;
- usage scanner age;
- object usage growth.

### Prometheus alerts

Default rules:

- `SiloMetricsAbsent` — monitoring target missing;
- `SiloTargetDown` — scrape target down;
- `SiloNodeOffline` — cluster node offline;
- `SiloDriveOffline` — drive offline;
- `SiloErasureSetUnhealthy` — erasure health failed;
- `SiloCapacityLow` — usable free capacity below 15%;
- `SiloCapacityCritical` — usable free capacity below 5%;
- `SiloUsageDataStale` — scanner data older than 24 hours;
- `SiloS3ErrorRateHigh` — error ratio above 5% for sustained traffic.

Thresholds are values in `charts/silo/values.yaml` so delivery environments can override them without modifying templates.

If Prometheus Operator CRDs do not exist, the installer disables ServiceMonitor/PrometheusRule creation instead of failing object-storage installation. The Grafana dashboard is a normal ConfigMap and remains available for environments where Grafana sidecar discovery is added later.

## Why fresh install and migration remain separate

The existing legacy installation uses the Bitnami MinIO chart. Even when the object data format is compatible, StatefulSet immutable fields, PVC template names, entrypoints and security contexts can differ.

Do not directly Helm-upgrade the legacy StatefulSet to this chart and do not run mixed MinIO/SILO nodes in the same erasure set. Existing installations require a separate migration procedure: inventory and snapshot/copy data, stop the old distributed cluster as a unit, start all SILO nodes on one pinned build, validate data/IAM/S3 behavior/monitoring, then retain a tested rollback path.

## Security defaults

- no `minioadmin` default credential;
- `silo-admin` username with a random first-install password;
- credentials stored in Kubernetes Secret and omitted from Helm argv;
- existing Secret is never rotated automatically;
- NodePort without TLS emits an explicit warning;
- non-root UID/GID `1001` retained for data ownership compatibility;
- privilege escalation disabled;
- all Linux capabilities dropped;
- RuntimeDefault seccomp;
- PDB and pod anti-affinity;
- fixed upstream source SHA;
- no customer-side `jq` dependency;
- `.run` installer SHA-256 verification.

## Production acceptance gate

Before production use validate in the actual Kubernetes/storage/Prometheus/Grafana environment:

- `mc cp`, download and `mc mirror`;
- S3 PUT/GET/DELETE/multipart and presigned URLs;
- Console login with Secret credentials;
- NodePort reachability on the intended network only;
- bucket policies, service accounts, versioning and lifecycle;
- SSE/KMS and object lock if used;
- Milvus/dataprotection S3 clients where applicable;
- `/minio/metrics/v3` target UP for every expected pod;
- dashboard panels populated with V3 metrics;
- alert rules load successfully and test alerts can be induced safely;
- four-node quorum, one-node loss/recovery and restart with existing `.minio.sys`;
- rollback from protected snapshot/copy.

## AGPL delivery note

SILO server, Console and MCLI are AGPL-3.0-or-later. Preserve licenses/attribution and satisfy corresponding-source obligations that apply to the distributed build. Keep `SILO_SOURCE.env`, upstream source location, exact source commit and notices in the delivery BOM. This is operational guidance, not legal advice.
