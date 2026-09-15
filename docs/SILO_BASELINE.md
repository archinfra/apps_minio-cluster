# PGSTY SILO delivery baseline

## Decision

New object-storage deliveries use PGSTY SILO as the maintained MinIO-compatible backend candidate.

Pinned baseline:

- Server: `RELEASE.2026-09-03T13-18-01Z`
- License: `AGPL-3.0-or-later`
- Architectures: `linux/amd64`, `linux/arm64`
- Default topology: 4-node distributed, 1 drive per node
- Default exposure: `ClusterIP`
- Default monitoring: metrics + ServiceMonitor + PrometheusRule when the CRDs exist
- Default credentials: Kubernetes Secret; no password is passed to Helm argv
- Offline installer build/runtime: no `jq` dependency

SILO preserves the MinIO-facing compatibility contract: S3 API, `MINIO_*` variables,
`minio_*` metrics, `/minio/*` routes and `.minio.sys` disk format. This makes it a
strong migration candidate, but it does not make a Bitnami Helm release structurally
identical to the SILO chart.

## Why this is a side-by-side baseline first

The existing `apps_minio-cluster` release uses the Bitnami MinIO chart. Even when
the object data format is compatible, StatefulSet fields, image entrypoints, PVC
template names, securityContext defaults and helper jobs can differ.

For that reason the first SILO delivery is intentionally a fresh-install baseline:

1. build the SILO `.run` artifact;
2. install into an isolated namespace/release;
3. validate S3 behavior and monitoring;
4. validate amd64 and arm64;
5. run a four-node failure/restart test;
6. rehearse MinIO-to-SILO migration with a copied/snapshotted data set;
7. only then define the production in-place migration procedure.

Do not run a mixed MinIO/SILO distributed cluster. Stop the old cluster as a unit
and start all SILO nodes on one pinned build during migration.

## Security baseline

The delivery changes several unsafe defaults from the legacy MinIO package:

- no hard-coded `minioadmin` password;
- credentials live in an existing Kubernetes Secret;
- reruns never rotate an existing Secret;
- API and Console default to `ClusterIP`, not `NodePort`;
- external exposure without TLS emits a warning;
- non-root UID/GID `1001` is retained to ease Bitnami data ownership compatibility;
- privilege escalation is disabled;
- all Linux capabilities are dropped;
- `RuntimeDefault` seccomp is enabled;
- immutable release tags are used;
- `jq` is not required by either build or install scripts.

The standard SILO image is used in v0.2.0 because it is the upstream default and
keeps operational tooling available. A distroless profile should be evaluated
after functional and recovery tests.

## Migration acceptance gate

Before changing an existing production MinIO release, validate:

- PUT / GET / DELETE and multipart upload
- presigned URLs
- bucket policies and service accounts
- versioning and lifecycle
- SSE/KMS if used
- object lock if used
- Milvus and dataprotection S3 clients
- Prometheus metrics and alerts
- four-node quorum behavior
- one-node loss and recovery
- restart with existing `.minio.sys`
- rollback to the recorded old MinIO image against a snapshot/copy

The current branch does not automatically attach legacy PVCs. That migration step
must be explicit and tested per the existing StatefulSet/PVC names.

## AGPL delivery note

SILO server, Console and MCLI are AGPL-3.0-or-later. Commercial use and
redistribution are permitted under that license, but delivery must preserve the
license/attribution and satisfy the corresponding-source obligations that apply to
the distributed build. Keep the exact upstream tag/commit and source location in
the delivery BOM. This note is operational guidance, not legal advice.
