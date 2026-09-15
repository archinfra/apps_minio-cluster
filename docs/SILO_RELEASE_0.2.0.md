# SILO Cluster Offline Delivery 0.2.0

## Release purpose

Version 0.2.0 establishes PGSTY SILO as the maintained MinIO-compatible object-storage baseline for new Archinfra private-delivery installations.

It is intentionally delivered side-by-side with the legacy MinIO package. Existing Bitnami MinIO StatefulSets are not upgraded in place by this release.

## Component baseline

| Component | Baseline |
| --- | --- |
| Archinfra installer | `0.2.0` |
| SILO upstream base | `RELEASE.2026-09-03T13-18-01Z` |
| SILO source commit | `1233254309b15571f101b2b26d531951ceaeef1e` |
| Security boundary | includes `SN-2026-011` fix |
| Image tag | `2026.09.03-sn011.123325430` |
| Architectures | `amd64`, `arm64` |
| Default topology | 4-node distributed / 1 drive per node |
| Default service exposure | ClusterIP |
| Default storage | `nfs`, `500Gi` per node |

## Why Archinfra builds the image from source

The latest SILO Server release published as of 2026-09-15 is still `RELEASE.2026-09-03T13-18-01Z`. The upstream SN-2026-011 advisory states that release is affected and that the server fix starts with commit `1233254309b15571f101b2b26d531951ceaeef1e`.

Therefore 0.2.0 builds the classic SILO image from that exact commit instead of redistributing the affected release image. This is an Archinfra security-patched source build and is labeled accordingly.

## Security defaults

- No predictable default root password.
- Root credentials are stored in a Kubernetes Secret.
- Existing Secrets are reused and never rotated automatically.
- Credentials are not placed in Helm command arguments.
- S3 API and Console default to ClusterIP.
- TLS is supported through an existing Kubernetes TLS Secret.
- Container runs as non-root with privilege escalation disabled, all capabilities dropped, and RuntimeDefault seccomp.
- PDB and anti-affinity are enabled by default.
- ServiceMonitor and PrometheusRule are enabled when the required CRDs exist.
- Build/install scripts do not require host `jq`.
- Every offline `.run` artifact has a standard SHA-256 checksum file.

## MinIO/mc compatibility

The classic SILO image includes mcli and the legacy `mc` alias. Existing automation using `mc cp`, `mc mirror`, `mc ls`, `mc stat`, and normal S3 endpoints remains an explicit compatibility target.

After deployment, run:

```bash
./scripts/silo-mc-smoke.sh -n aict --release-name silo
```

The smoke test creates a temporary bucket and validates actual `mc`/`mcli` copy, download, stat, and mirror behavior, then removes the test bucket.

## Installation

Verify the artifact first:

```bash
sha256sum -c silo-cluster-installer-0.2.0-amd64.run.sha256
```

Install using the safe internal-only defaults:

```bash
chmod +x silo-cluster-installer-0.2.0-amd64.run
./silo-cluster-installer-0.2.0-amd64.run install -y
```

For external exposure, explicitly select NodePort/LoadBalancer and enable TLS. Do not expose the S3 API or Console over an untrusted network without TLS and appropriate network policy/firewall controls.

## Existing MinIO installations

Do not perform `helm upgrade` from the legacy Bitnami chart directly to this chart. Data-format compatibility does not make StatefulSet/PVC templates structurally interchangeable.

For existing clusters use a controlled migration procedure:

1. inventory StatefulSet, PVCs, storage class, UID/GID and current credentials;
2. verify backups or storage snapshots;
3. stop the MinIO cluster as a unit;
4. attach copied/snapshotted data to a SILO migration rehearsal;
5. validate S3, IAM, versioning, lifecycle, monitoring and application clients;
6. test node failure/recovery and rollback;
7. only then schedule production cutover.

Never operate a mixed MinIO/SILO distributed cluster on the same erasure set.

## Release acceptance

CI must pass all of the following before merge:

- shell syntax validation;
- pinned-source metadata validation;
- Helm lint and template rendering;
- source build for amd64;
- source build for arm64;
- `silo --version` in both built images;
- `mc --version` and `mc cp --help` in both built images;
- SHA-256 installer verification;
- final offline artifact upload.
