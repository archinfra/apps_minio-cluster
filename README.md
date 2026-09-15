# apps_minio-cluster

S3 兼容对象存储的离线私有化交付仓库。

> **当前新部署基线：PGSTY SILO 0.2.2。**
>
> 旧 Bitnami MinIO 2025.7.23 已进入 legacy 路径，仅用于已有环境维护、回滚和迁移演练。不要再把旧 MinIO 作为新的生产交付基线。

## 当前版本

Archinfra `0.2.2`：

- Backend：PGSTY SILO
- Upstream base：`RELEASE.2026-09-03T13-18-01Z`
- Security-fixed source：`1233254309b15571f101b2b26d531951ceaeef1e`
- 修复边界：包含 `SN-2026-011`
- Image tag：`2026.09.03-sn011.123325430`
- 架构：`amd64` / `arm64`
- 默认拓扑：4 节点 distributed，1 drive/node
- 默认存储：`nfs`，每节点 `500Gi`
- S3 API：`NodePort 30095`
- Web Console：`NodePort 30092`
- 默认用户：`silo-admin`
- 默认密码：首次安装随机生成并写入 `silo-root-credentials`
- 默认监控：Metrics V3 + ServiceMonitor + PrometheusRule + Grafana Dashboard
- 客户离线环境：不依赖 `jq`

详细版本和安全边界见：

- `docs/SILO_RELEASE_0.2.2.md`
- `docs/SILO_BASELINE.md`
- `SILO_SOURCE.env`

## 快速安装

```bash
sha256sum -c silo-cluster-installer-0.2.2-amd64.run.sha256
chmod +x silo-cluster-installer-0.2.2-amd64.run
./silo-cluster-installer-0.2.2-amd64.run install -y
```

默认部署契约：

- namespace：`aict`
- release：`silo`
- replicas：`4`
- storageClass：`nfs`
- storage：`500Gi` / node
- S3 API：`http://<NODE_IP>:30095`
- Console：`http://<NODE_IP>:30092`
- Secret：`silo-root-credentials`

默认通过 NodePort 暴露是为了私有化交付和现场运维便利；生产网络必须通过防火墙、ACL、NetworkPolicy 或网关限制可达范围。跨不可信网络暴露时应启用 TLS。

## 登录认证

SILO Console 与 S3 root 凭据共用 Kubernetes Secret。

首次安装时：

- 用户名默认 `silo-admin`
- 密码随机生成，长度 48 hex 字符
- 密码不会进入 Helm argv
- 重复执行安装不会自动轮换已有 Secret

查看当前凭据：

```bash
./silo-cluster-installer-0.2.2-amd64.run credentials
```

查看访问地址：

```bash
./silo-cluster-installer-0.2.2-amd64.run endpoint
```

也可以显式提供密码：

```bash
./silo-cluster-installer-0.2.2-amd64.run install \
  --root-user silo-admin \
  --root-password 'CHANGE-ME-STRONG-PASSWORD' \
  -y
```

## NodePort 与 TLS

默认：

| 接口 | Pod/Service Port | NodePort |
|---|---:|---:|
| S3 API | 9000 | 30095 |
| Web Console | 9001 | 30092 |

启用 TLS：

```bash
./silo-cluster-installer-0.2.2-amd64.run install \
  --enable-tls \
  --tls-secret silo-tls \
  -y
```

## Web Console

SILO 自带完整 HTTP 管理 Console，默认监听 `9001`，本交付默认通过 `30092` 暴露。

Console 用于 Bucket/Object、用户/Policy/Service Account、集群与磁盘健康、生命周期/复制/通知、日志诊断和内置 Metrics 页面。

## `mc` / `mcli` 兼容

SILO classic image 内置 `mcli`，同时提供 `/usr/bin/mc` 兼容入口：

```bash
mc alias set storage http://silo:9000 ACCESS_KEY SECRET_KEY
mc cp backup.tar storage/backups/
mc mirror ./dir storage/bucket/path/
mc ls storage/bucket/
mc stat storage/bucket/backup.tar
```

CI 会验证 `silo --version`、`mc --version` 和 `mc cp --help`。

## 监控

0.2.2 使用 SILO/MinIO **Metrics V3**：

```text
/minio/metrics/v3
```

默认创建：

- `ServiceMonitor`
- `PrometheusRule`
- Grafana Dashboard ConfigMap（`grafana_dashboard=1`）

Dashboard：`SILO Object Storage Overview`

覆盖节点/磁盘健康、容量、Bucket/Object、S3 请求与错误、流量、CPU/内存、磁盘使用、Usage Data Age 和 Erasure Health。

默认告警：`SiloTargetDown`、`SiloMetricsMissing`、`SiloNodeOffline`、`SiloDriveOffline`、`SiloErasureSetUnhealthy`、`SiloCapacityLow`、`SiloCapacityCritical`、`SiloUsageDataStale`、`SiloS3ErrorsDetected`、`SiloS3ErrorRatioHigh`。

V3 的 cluster 指标会在多个节点重复暴露，所以 Dashboard/Rules 对 cluster 指标使用 `max()` / `min()`；对 V3 “零值不导出”行为增加必要 zero-guard。

如果集群不存在 ServiceMonitor/PrometheusRule CRD，安装器自动关闭对应对象，不影响 SILO 主安装流程。Grafana Dashboard ConfigMap 仍会创建，供已有 Grafana sidecar 发现。

## 运维命令

```bash
./silo-cluster-installer-0.2.2-amd64.run status
./silo-cluster-installer-0.2.2-amd64.run credentials
./silo-cluster-installer-0.2.2-amd64.run endpoint
./silo-cluster-installer-0.2.2-amd64.run uninstall
```

卸载时 PVC 和凭据 Secret 默认保留。

## 安全默认值

- 不使用固定 `minioadmin` 密码
- 密码不进入 Helm argv
- Kubernetes Secret 管理 root 凭据
- 支持 TLS Secret
- `runAsNonRoot=true`
- `allowPrivilegeEscalation=false`
- `capabilities.drop=[ALL]`
- `seccompProfile=RuntimeDefault`
- PDB / Pod anti-affinity
- 固定上游源码 SHA
- `.run` 提供 SHA-256
- Silo 构建/安装流程不依赖 `jq`

注意：0.2.2 按交付要求默认打开 NodePort；生产环境必须配合网络边界控制，跨不可信网络时应启用 TLS。

## 现有 MinIO 怎么办

**不要直接执行 Bitnami MinIO Chart → SILO Chart 的 `helm upgrade`。**

已有生产 MinIO 应先做 snapshot/可恢复备份，再按单独迁移流程演练；禁止同一个 erasure set 中混跑 MinIO 和 SILO 节点。

## 构建

```bash
./build-silo.sh --arch amd64
./build-silo.sh --arch arm64
```

构建产物：

```text
dist/silo-cluster-installer-0.2.2-amd64.run
dist/silo-cluster-installer-0.2.2-amd64.run.sha256
dist/silo-cluster-installer-0.2.2-arm64.run
dist/silo-cluster-installer-0.2.2-arm64.run.sha256
```

## Release gate

合并/发布前必须满足 shell syntax、固定源码 SHA、版本一致性、tag/version 一致性、Helm lint/render、NodePort、Metrics V3、Grafana Dashboard、关键 PrometheusRule、双架构 source build、`mc` 兼容和 installer SHA-256 校验。
