# app_minio-cluster

MinIO Cluster offline delivery project for Kubernetes.

This repository keeps the existing MinIO runtime defaults and upgrades the
delivery layer to the same style used in the MySQL and Redis repositories:

- multi-arch offline installers for `amd64` and `arm64`
- metadata-driven embedded image payloads
- explicit internal-registry image rendering during Helm install
- GitHub Actions build and GitHub Release publishing

The business defaults are intentionally preserved:

- namespace: `aict`
- release name: `minio`
- mode: `distributed`
- replicas: `4`
- drives per node: `1`
- storage class: `nfs`
- storage size: `500Gi`
- API service type: `NodePort`
- API nodePort: `30093`
- console enabled: `true`
- console service type: `NodePort`
- console nodePort: `30092`
- metrics: `enabled`
- ServiceMonitor: `enabled`

## Layout

- `build.sh`: build multi-arch `.run` installers
- `install.sh`: self-extracting offline installer template
- `images/image.json`: multi-arch image manifest
- `charts/minio`: vendored MinIO Helm chart
- `.github/workflows/build-offline-installer.yml`: GitHub Actions build and release

## Local Build

Requirements:

- `bash`
- `docker`
- `jq`

Examples:

```bash
./build.sh --arch amd64
./build.sh --arch arm64
./build.sh --arch all
```

Artifacts are generated in `dist/`:

- `minio-cluster-installer-amd64.run`
- `minio-cluster-installer-amd64.run.sha256`
- `minio-cluster-installer-arm64.run`
- `minio-cluster-installer-arm64.run.sha256`

## Installer Usage

Show help:

```bash
./minio-cluster-installer-amd64.run --help
./minio-cluster-installer-amd64.run help
```

Install with the preserved defaults:

```bash
./minio-cluster-installer-amd64.run install -y
```

Install with the preserved defaults, including Prometheus operator integration:

```bash
./minio-cluster-installer-amd64.run install -y
```

Reuse images already present in the target registry:

```bash
./minio-cluster-installer-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --skip-image-prepare \
  -y
```

Show status:

```bash
./minio-cluster-installer-amd64.run status -n aict
```

Uninstall:

```bash
./minio-cluster-installer-amd64.run uninstall -n aict -y
```

## Monitoring

Monitoring is enabled by default:

- `--enable-metrics` enables MinIO metrics endpoint exposure
- `--enable-servicemonitor` creates a `ServiceMonitor`
- the installer and chart both add `monitoring.archinfra.io/stack=default` for automatic discovery by the platform Prometheus stack
- `--disable-metrics` also disables `ServiceMonitor`
- if the cluster does not contain the `ServiceMonitor` CRD, the installer warns and downgrades automatically

## GitHub Actions Release Flow

Push to `main`:

- build `amd64` and `arm64` installers
- upload installer artifacts

Push a `v*` tag:

- build both architectures
- publish `.run` packages and `.sha256` files to GitHub Release
