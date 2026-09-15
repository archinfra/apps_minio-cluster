# SILO 0.2.2 Release Notes

Archinfra SILO `0.2.2` is a release-correctness update on top of the 0.2.1 operations and monitoring baseline.

## Changes

- Move the default SILO S3 API NodePort from `30093` to `30095` to avoid the standard Alertmanager NodePort `30093` used by the Archinfra monitoring stack.
- Keep the SILO Web Console NodePort at `30092`.
- Keep the security-fixed SILO source pinned to `1233254309b15571f101b2b26d531951ceaeef1e` with `SN-2026-011` included.
- Keep Metrics V3, ServiceMonitor, PrometheusRule and Grafana Dashboard enabled by default when the corresponding CRDs are available.
- Align `VERSION`, Helm chart version and installer version to `0.2.2`.
- Make CI release validation derive the expected version from `VERSION` instead of hard-coding a release number, and validate tag/version consistency.

## Default endpoints

- S3 API: `http://<NODE_IP>:30095`
- Web Console: `http://<NODE_IP>:30092`

## Compatibility

- Architectures: `linux/amd64`, `linux/arm64`
- S3/MinIO API compatibility remains unchanged.
- The image continues to include the `mc` compatibility entrypoint.
- Existing deployments that explicitly configured NodePorts are unaffected. The new `30095` value is the default for fresh installs only.

## Release gate

The release workflow must pass shell syntax checks, source-pin validation, release metadata consistency, Helm lint/render, NodePort assertions, Metrics V3/Dashboard/alert checks, dual-architecture source builds, `mc` compatibility checks and installer SHA-256 verification.
