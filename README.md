# apps_minio-cluster

S3 兼容对象存储离线私有化交付仓库。

> 当前新部署基线：**PGSTY SILO 0.2.1**。
> 旧 Bitnami MinIO 2025.7.23 仅保留给已有环境维护、回滚和迁移演练。

## 当前版本

- Archinfra：`0.2.1`
- Backend：PGSTY SILO
- Upstream base：`RELEASE.2026-09-03T13-18-01Z`
- Security-fixed source：`1233254309b15571f101b2b26d531951ceaeef1e`
- 修复边界：包含 `SN-2026-011`
- Image tag：`2026.09.03-sn011.123325430`
- 架构：`amd64` / `arm64`
- 默认拓扑：4 节点 distributed，1 drive/node
- 默认存储：`nfs`，500Gi/node
- S3 API：NodePort `30093`
- Web Console：NodePort `30092`
- 默认 Console/root 用户：`silo-admin`
- 密码：首次安装随机生成并写入 Kubernetes Secret
- 默认监控：Metrics V3 + ServiceMonitor + PrometheusRule + Grafana Dashboard
- 客户离线环境：不依赖 `jq`

## 安装

```bash
sha256sum -c silo-cluster-installer-0.2.1-amd64.run.sha256
chmod +x silo-cluster-installer-0.2.1-amd64.run
./silo-cluster-installer-0.2.1-amd64.run install -y
```

默认：

```text
namespace: aict
release: silo
S3:      http://<NODE_IP>:30093
Console: http://<NODE_IP>:30092
Secret:  silo-root-credentials
user:    silo-admin
password: first-install random strong password
```

已有 `silo-root-credentials` 时会直接复用，不自动轮换。密码不会进入 Helm argv。

## 登录认证与访问

查看访问地址：

```bash
./silo-cluster-installer-0.2.1-amd64.run endpoint -n aict
```

显式查看 Console/S3 root 凭据：

```bash
./silo-cluster-installer-0.2.1-amd64.run credentials -n aict
```

自定义首次安装账号密码：

```bash
./silo-cluster-installer-0.2.1-amd64.run install \
  --root-user storage-admin \
  --root-password 'YourStrongPasswordHere' \
  -y
```

需要改回 ClusterIP：

```bash
./silo-cluster-installer-0.2.1-amd64.run install \
  --service-type ClusterIP \
  --console-service-type ClusterIP \
  -y
```

默认 NodePort 是为了私有化交付现场易用性；如果访问边界不完全可信，应启用 TLS：

```bash
./silo-cluster-installer-0.2.1-amd64.run install \
  --enable-tls \
  --tls-secret silo-tls \
  -y
```

## Web Console

SILO 保留 MinIO 兼容的 Web Console，服务端监听 `9001`，本交付默认通过 NodePort `30092` 暴露。Console 使用与 S3 root 相同的 Secret 认证。

## `mc` 兼容

SILO classic image 内置 `mcli`，并提供 `/usr/bin/mc -> mcli` 兼容入口：

```bash
mc alias set storage http://silo:9000 ACCESS_KEY SECRET_KEY
mc cp backup.tar storage/backups/
mc mirror ./dir storage/bucket/path/
mc ls storage/bucket/
mc stat storage/bucket/backup.tar
```

CI 会实际验证：

```text
/usr/bin/silo --version
/usr/bin/mc --version
/usr/bin/mc cp --help
```

部署后可执行 `scripts/silo-mc-smoke.sh` 做真实上传、下载、stat 和 mirror 验收。

## 监控

### ServiceMonitor

默认抓取 SILO/MinIO Metrics V3：

```text
/minio/metrics/v3
```

`ServiceMonitor` 默认带：

```yaml
monitoring.archinfra.io/stack: default
```

### Grafana Dashboard

默认创建：

```text
ConfigMap: silo-dashboard
Dashboard: SILO Cluster Overview
```

标签：

```yaml
grafana_dashboard: "1"
monitoring.archinfra.io/stack: default
```

主要覆盖：

- Prometheus scrape targets
- Online / Offline Nodes
- Online / Offline Drives
- Erasure Health
- Usable / Free Capacity
- Free Capacity %
- Bucket / Object 数量
- S3 Request Rate / Error Rate
- S3 Ingress / Egress
- Internode Traffic
- Node CPU / Memory
- Drive Used
- Usage Data Age
- Object Usage Growth

### PrometheusRule

默认告警：

| Alert | Severity | 含义 |
| --- | --- | --- |
| `SiloMetricsAbsent` | warning | Prometheus 没发现 SILO target |
| `SiloTargetDown` | critical | SILO target 持续抓取失败 |
| `SiloNodeOffline` | critical | 节点离线 |
| `SiloDriveOffline` | critical | 磁盘离线 |
| `SiloErasureSetUnhealthy` | critical | Erasure Set 不健康 |
| `SiloCapacityLow` | warning | 可用容量低于 15% |
| `SiloCapacityCritical` | critical | 可用容量低于 5% |
| `SiloUsageDataStale` | warning | Usage Scanner 超过 24h 未刷新 |
| `SiloS3ErrorRateHigh` | warning | 有业务流量时 S3 错误率持续高于 5% |

如果集群没有 ServiceMonitor / PrometheusRule CRD，安装器会关闭对应对象创建，不影响对象存储主安装流程。Grafana Dashboard 是普通 ConfigMap。

## 状态检查

```bash
./silo-cluster-installer-0.2.1-amd64.run status -n aict
```

会查看 Helm、Pod、Service、PVC、ServiceMonitor、PrometheusRule 和 Dashboard ConfigMap。

## 安全默认值

- 无固定 `minioadmin` 密码
- 默认用户 `silo-admin`
- 随机强密码存 Kubernetes Secret
- 不通过 Helm argv 传密码
- 已有 Secret 不自动轮换
- NodePort 无 TLS 时安装器明确告警
- `runAsNonRoot=true`
- `allowPrivilegeEscalation=false`
- `capabilities.drop=[ALL]`
- `seccompProfile=RuntimeDefault`
- PDB + Pod anti-affinity
- 固定上游安全修复源码 SHA
- `.run` 带 SHA-256 校验

## 现有 MinIO 迁移

不要直接对旧 Bitnami MinIO StatefulSet 执行原地 Helm upgrade 到 SILO。SILO 保留 S3、`MINIO_*`、`minio_*` 和 `.minio.sys` 兼容，但 StatefulSet/PVC template/securityContext 并不等价。

迁移必须先 snapshot/copy，整组停止旧 MinIO，再用同一固定 SILO build 启动并验证；禁止同一 erasure set 混跑 MinIO/SILO。

## 构建

```bash
./build-silo.sh --arch amd64
./build-silo.sh --arch arm64
```

产物：

```text
dist/silo-cluster-installer-0.2.1-amd64.run
dist/silo-cluster-installer-0.2.1-amd64.run.sha256
dist/silo-cluster-installer-0.2.1-arm64.run
dist/silo-cluster-installer-0.2.1-arm64.run.sha256
```

详细基线见 `docs/SILO_BASELINE.md` 和 `docs/SILO_RELEASE_0.2.1.md`。
