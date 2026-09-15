# PGSTY SILO delivery baseline

## Decision

New object-storage deliveries use PGSTY SILO as the maintained MinIO-compatible backend.
The legacy Bitnami MinIO path remains only for rollback and controlled migration work.

Archinfra release `0.2.0` pins:

- Upstream project: `pgsty/silo`
- Upstream base release: `RELEASE.2026-09-03T13-18-01Z`
- Security-fixed source commit: `1233254309b15571f101b2b26d531951ceaeef1e`
- Security advisory addressed by the source pin: `SN-2026-011`
- Archinfra image tag: `2026.09.03-sn011.123325430`
- License: `AGPL-3.0-or-later`
- Architectures: `linux/amd64`, `linux/arm64`
- Default topology: 4-node distributed, 1 drive per node
- Default exposure: `ClusterIP`
- Default monitoring: metrics + ServiceMonitor + PrometheusRule when the CRDs exist
- Default credentials: Kubernetes Secret; no password is passed to Helm argv
- Offline installer runtime: no `jq` dependency

## Security release boundary

As of 2026-09-15, SILO's latest published Server release remains
`RELEASE.2026-09-03T13-18-01Z`. SILO's security advisory for SN-2026-011 states
that this published release is affected and that the fix starts at source commit
`1233254309b15571f101b2b26d531951ceaeef1e`.

For that reason Archinfra 0.2.0 does **not** redistribute the vulnerable published
Server image. The build pipeline fetches the exact fixed source commit, verifies the
40-character Git SHA, builds the classic SILO container for the requested architecture,
and packages that locally built image into the offline installer.

This is intentionally an Archinfra security-patched source build, not an upstream
SILO release. When SILO publishes a later Server release that explicitly contains
SN-2026-011, move the baseline back to an upstream release after compatibility tests.

## MinIO compatibility contract

SILO preserves the MinIO-facing compatibility contract: S3 API, `MINIO_*` variables,
`minio_*` metrics, `/minio/*` routes and `.minio.sys` disk format.

The classic SILO image also ships `mcli` with the legacy `mc` compatibility alias.
Existing client-side automation using commands such as the following is an explicit
acceptance target:

```bash
mc alias set storage http://silo:9000 ACCESS_KEY SECRET_KEY
mc cp backup.tar storage/backups/
mc mirror ./directory storage/bucket/path/
mc ls storage/bucket/
mc stat storage/bucket/backup.tar
```

Run `scripts/silo-mc-smoke.sh` after installation to exercise real `mc/mcli` upload,
download, stat and mirror behavior against the deployed cluster.

## Why fresh install and migration remain separate

The existing `apps_minio-cluster` release uses the Bitnami MinIO chart. Even when
the object data format is compatible, StatefulSet fields, image entrypoints, PVC
template names, securityContext defaults and helper jobs can differ.

Therefore 0.2.0 defines the SILO fresh-install baseline and does not automatically
attach existing MinIO PVCs. Existing installations require a separate migration runbook.

Do not run a mixed MinIO/SILO distributed cluster. Stop the old cluster as a unit,
protect the data with a snapshot/copy, and start all SILO nodes on one pinned build.

## Security defaults

The delivery changes several unsafe defaults from the legacy MinIO package:

- no hard-coded `minioadmin` password;
- credentials live in a Kubernetes Secret;
- reruns never rotate an existing Secret;
- API and Console default to `ClusterIP`, not `NodePort`;
- external exposure without TLS emits a warning;
- non-root UID/GID `1001` is retained to ease Bitnami data ownership compatibility;
- privilege escalation is disabled;
- all Linux capabilities are dropped;
- `RuntimeDefault` seccomp is enabled;
- source commit and image tag are pinned;
- build host and customer installer do not require `jq`;
- generated `.run` installers ship standard SHA-256 checksum files.

## Production acceptance gate

Before using the build for a production workload, validate in the target Kubernetes
and storage environment:

- `mc cp` upload/download and `mc mirror`
- PUT / GET / DELETE and multipart upload
- presigned URLs, including CopyObject-related application flows
- bucket policies and service accounts
- versioning and lifecycle
- SSE/KMS if used
- object lock if used
- Milvus and dataprotection S3 clients if applicable
- Prometheus metrics and alerts
- four-node quorum behavior
- one-node loss and recovery
- restart with existing `.minio.sys`
- rollback against a protected snapshot/copy

## AGPL delivery note

SILO server, Console and MCLI are AGPL-3.0-or-later. Commercial use and
redistribution are permitted under that license, but delivery must preserve the
license/attribution and satisfy corresponding-source obligations that apply to the
distributed build. Keep `SILO_SOURCE.env`, the upstream source location, exact commit
and notices with the delivery BOM. This is operational guidance, not legal advice.
