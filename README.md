# apps_minio-cluster

S3 兼容对象存储的离线私有化交付仓库。

> **当前新部署基线：PGSTY SILO 0.2.0。**
>
> 旧 Bitnami MinIO 2025.7.23 已进入 legacy 路径，仅用于已有环境维护、回滚和迁移演练。不要再把旧 MinIO 作为新的生产交付基线。

## 当前版本

Archinfra `0.2.0`：

- Backend：PGSTY SILO
- Upstream base：`RELEASE.2026-09-03T13-18-01Z`
- Security-fixed source：`1233254309b15571f101b2b26d531951ceaeef1e`
- 修复边界：包含 `SN-2026-011`
- Image tag：`2026.09.03-sn011.123325430`
- 架构：`amd64` / `arm64`
- 默认拓扑：4 节点 distributed，1 drive/node
- 默认存储：`nfs`，每节点 `500Gi`
- 默认暴露：S3 API / Console 均为 `ClusterIP`
- 默认监控：metrics + ServiceMonitor + PrometheusRule
- 凭据：Kubernetes Secret，不通过 Helm argv 传密码
- 客户离线环境：不依赖 `jq`

详细版本和安全边界见：

- `docs/SILO_RELEASE_0.2.0.md`
- `docs/SILO_BASELINE.md`
- `SILO_SOURCE.env`

## 为什么不是直接使用 SILO 2026-09-03 官方镜像

截至 2026-09-15，SILO 最新正式 Server release 仍是 `RELEASE.2026-09-03T13-18-01Z`，但上游安全公告明确说明该 release 仍受 `SN-2026-011` 影响，修复从 source commit `1233254309b15571f101b2b26d531951ceaeef1e` 开始。

因此 Archinfra `0.2.0`：

1. 固定上游源码 SHA；
2. CI 从该 SHA 编译 SILO；
3. 分别构建 amd64 / arm64 镜像；
4. 将镜像封装进自解压 `.run` 离线包；
5. 使用独立 Archinfra image tag，避免冒充上游正式 release。

## 快速安装

校验安装包：

```bash
sha256sum -c silo-cluster-installer-0.2.0-amd64.run.sha256
```

安装：

```bash
chmod +x silo-cluster-installer-0.2.0-amd64.run
./silo-cluster-installer-0.2.0-amd64.run install -y
```

默认：

- namespace：`aict`
- release：`silo`
- replicas：`4`
- storageClass：`nfs`
- storage：`500Gi` / node
- S3：`ClusterIP:9000`
- Console：`ClusterIP:9001`
- Secret：`silo-root-credentials`

如果 Secret 不存在，安装器会生成随机强密码并创建 Secret；如果 Secret 已存在，则直接复用，不自动轮换。

## 对外暴露

默认不再通过 NodePort 暴露 API/Console。

确实需要 NodePort 时显式开启：

```bash
./silo-cluster-installer-0.2.0-amd64.run install \
  --service-type NodePort \
  --console-service-type NodePort \
  --api-node-port 30093 \
  --console-node-port 30092 \
  -y
```

生产环境对外暴露时应同时配置 TLS：

```bash
./silo-cluster-installer-0.2.0-amd64.run install \
  --service-type NodePort \
  --enable-tls \
  --tls-secret silo-tls \
  -y
```

## `mc cp` 是否兼容

兼容。

SILO classic image 内置 `mcli`，同时提供旧 `mc` 兼容入口。因此原有脚本的核心调用方式仍作为交付验收目标：

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

部署完成后还可以执行真实读写 smoke test：

```bash
./scripts/silo-mc-smoke.sh -n aict --release-name silo
```

它会创建临时 bucket，执行 `mc cp` 上传、`stat`、下载校验、`mc mirror`，最后自动清理测试 bucket。

## 监控

默认启用：

- SILO Prometheus metrics
- ServiceMonitor
- PrometheusRule

如果集群不存在对应 Prometheus Operator CRD，安装器会自动关闭对应对象创建，不让对象存储主安装流程失败。

## 安全默认值

- 无固定 `minioadmin` 默认密码
- 密码不进入 Helm argv
- 默认 ClusterIP
- 支持 TLS Secret
- `runAsNonRoot=true`
- `allowPrivilegeEscalation=false`
- `capabilities.drop=[ALL]`
- `seccompProfile=RuntimeDefault`
- PDB
- Pod anti-affinity
- 固定上游源码 SHA
- `.run` 提供标准 SHA-256 校验文件

## 现有 MinIO 怎么办

**不要直接执行 Bitnami MinIO Chart → SILO Chart 的 `helm upgrade`。**

SILO 保留 S3 API、`MINIO_*`、`minio_*` metrics、`/minio/*` 和 `.minio.sys` 数据格式兼容，但 Helm StatefulSet、PVC template、entrypoint 和安全上下文并不等同。

已有生产 MinIO 应按单独迁移流程处理：

1. 记录现有版本、StatefulSet、PVC、StorageClass、Secret 和 UID/GID；
2. 做存储 snapshot / 可恢复备份；
3. 停止整个 MinIO distributed cluster；
4. 用复制或快照数据演练 SILO 启动；
5. 验证 bucket、对象、IAM、versioning、lifecycle、S3 SDK、`mc`、监控；
6. 验证节点故障、恢复和回滚；
7. 再做正式切换。

禁止同一个 erasure set 中混跑 MinIO 和 SILO 节点。

## 仓库结构

```text
VERSION                    Archinfra 交付版本
SILO_SOURCE.env            上游源码、基线和安全修复 SHA
build-silo.sh              SILO 源码构建 + 离线包生成
install-silo.sh            SILO 自解压离线安装器
scripts/silo-mc-smoke.sh   mc/mcli 真实读写兼容测试
charts/silo/               Archinfra SILO Helm chart
images/silo-image-index.tsv 双架构目标镜像清单
docs/SILO_BASELINE.md      安全、兼容和迁移基线
docs/SILO_RELEASE_0.2.0.md 0.2.0 正式交付说明

build.sh / install.sh / charts/minio/
                           legacy MinIO，仅用于已有环境/回滚/迁移
```

## 构建

构建单架构：

```bash
./build-silo.sh --arch amd64
./build-silo.sh --arch arm64
```

CI 使用 Go `1.27.1`，从 `SILO_SOURCE.env` 指定的精确 commit 拉取并构建 upstream SILO classic image。

构建产物：

```text
dist/silo-cluster-installer-0.2.0-amd64.run
dist/silo-cluster-installer-0.2.0-amd64.run.sha256
dist/silo-cluster-installer-0.2.0-arm64.run
dist/silo-cluster-installer-0.2.0-arm64.run.sha256
```

## Release gate

合并/发布前必须满足：

- `bash -n`
- 固定源码 SHA 校验
- `helm lint`
- `helm template`
- amd64 source build
- arm64 source build
- `silo --version`
- `mc --version`
- `mc cp --help`
- installer SHA-256 verify
- GitHub Actions artifact 成功上传

只有这些门槛全部通过，才把对应 main commit 视为可交付版本。
