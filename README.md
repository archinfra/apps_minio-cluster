# apps_minio-cluster

MinIO 集群离线交付仓库。

这个仓库不是只放一个 Helm chart，而是把下面几件事做成了统一的 `.run` 安装包：

- MinIO 集群安装
- 内网镜像准备
- metrics / ServiceMonitor 接入
- `amd64` / `arm64` 多架构离线交付
- GitHub Actions 构建与 GitHub Release 发布

它沿用了 MySQL、Redis、Nacos、Milvus、RabbitMQ、MongoDB 这一批仓库的统一范式，目标是让没有背景信息的新同事，或者一个普通 AI，也能看着 README 完成安装、验证和排障。

## 这套安装器是怎么设计的

普通使用者可以把它理解成一个 “MinIO 集群离线安装器”，核心只有 4 个动作：

- `install`
- `status`
- `uninstall`
- `help`

其中 `install` 默认会自动完成：

1. 解包 `.run` 里的 chart、镜像元数据和镜像 tar
2. 将离线 payload 里的镜像准备到目标内网仓库
3. 检查集群是否支持 `ServiceMonitor`
4. 渲染最终 Helm 参数
5. 执行 `helm upgrade --install`
6. 输出 Pod、Service、PVC、ServiceMonitor 状态

这意味着普通使用者通常不需要自己手动做：

- `docker load`
- `docker tag`
- `docker push`
- `helm dependency build`
- 手工写 `ServiceMonitor`

## 默认部署契约

如果你直接执行：

```bash
./minio-cluster-installer-amd64.run install -y
```

默认值如下：

- namespace: `aict`
- release name: `minio`
- mode: `distributed`
- replicas: `4`
- drives per node: `1`
- access key: `minioadmin`
- secret key: `minioadmin@123`
- storage class: `nfs`
- storage size: `500Gi`
- API service type: `NodePort`
- API NodePort: `30093`
- console enabled: `true`
- console service type: `NodePort`
- console NodePort: `30092`
- metrics: `true`
- ServiceMonitor: `true`
- ServiceMonitor interval: `30s`
- target registry repo: `sealos.hub:5000/kube4`
- image pull policy: `IfNotPresent`
- wait timeout: `10m`

这是一套 “4 副本分布式 MinIO + 默认开启 Console + 默认开启监控” 的标准交付方案。

## 默认拓扑

默认安装会创建：

- 1 个 Helm release：`minio`
- 4 个 MinIO 数据节点
- 4 个 PVC
- 1 个 MinIO API Service
- 1 个 MinIO Console Service
- 1 个 `ServiceMonitor`，前提是集群支持 `ServiceMonitor` CRD
- 若干初始化 / provisioning 辅助 Pod

默认不会创建：

- 外部数据库
- 额外的业务 sidecar
- 单独的 Prometheus

也就是说，`apps_minio-cluster` 默认是一个相对独立的对象存储组件，不依赖 MySQL、Redis、Nacos 这些组件启动。

## 默认访问地址、端口和账户

### 集群内访问

MinIO API 默认可以通过下面的地址访问：

- `minio.aict.svc.cluster.local:9000`
- `http://minio.aict.svc.cluster.local:9000`

MinIO Console 默认可以通过下面的地址访问：

- `minio-console.aict.svc.cluster.local:9090`
- `http://minio-console.aict.svc.cluster.local:9090`

### 集群外访问

默认是 NodePort：

- API: `http://<NODE_IP>:30093`
- Console: `http://<NODE_IP>:30092`

### 默认账户

默认管理员凭据：

- Access Key: `minioadmin`
- Secret Key: `minioadmin@123`

建议：

- 测试环境可以沿用默认值
- 生产环境应在首次安装时显式改掉

## 和其他组件的依赖关系

### MinIO 依赖谁

默认不依赖：

- MySQL
- Redis
- Nacos
- RabbitMQ
- MongoDB
- Milvus

唯一前置要求主要是：

- Kubernetes 集群可用
- `StorageClass` 可正常动态供卷
- 如果不带 `--skip-image-prepare`，安装执行机需要有 `docker`

### 谁常常会依赖 MinIO

在整套系统里，MinIO 更常见的角色是“被其他系统消费”：

- Milvus
- 数据保护 / 备份恢复系统
- 业务系统对象存储上传下载
- 需要 S3 兼容接口的应用

### 和 Prometheus 的关系

MinIO 默认会创建带统一标签的 `ServiceMonitor`：

- `monitoring.archinfra.io/stack=default`

如果你的 Prometheus Stack 采用我们统一的按标签发现策略，MinIO 安装后通常会自动被发现。

## 默认资源需求

安装器对资源做了显式下发，默认值如下。

### 单个 MinIO 数据节点

- CPU request: `500m`
- Memory request: `1Gi`
- CPU limit: `4`
- Memory limit: `8Gi`

### MinIO Console

- CPU request: `100m`
- Memory request: `256Mi`
- CPU limit: `500m`
- Memory limit: `512Mi`

### provisioning / MinIO Client 辅助容器

- CPU request: `50m`
- Memory request: `64Mi`
- CPU limit: `200m`
- Memory limit: `256Mi`

### 默认持续资源总量

默认是 `4` 个数据节点，因此持续运行阶段大致是：

| 项目 | 默认总量 |
| --- | --- |
| MinIO 数据节点 CPU request | `2` |
| MinIO 数据节点 Memory request | `4Gi` |
| MinIO 数据节点 CPU limit | `16` |
| MinIO 数据节点 Memory limit | `32Gi` |
| Console CPU request | `100m` |
| Console Memory request | `256Mi` |
| Console CPU limit | `500m` |
| Console Memory limit | `512Mi` |

provisioning / MinIO Client 辅助容器不是常驻负载，但安装和初始化阶段会短暂占用资源。

## 存储需求

当前默认是：

- 4 个数据节点
- 每个节点 `500Gi`

因此默认最小持久化存储需求是：

- `2000Gi`，也就是 `2Ti`

如果你把副本数或单盘容量调高，整体存储需求会线性增加。

## 监控设计

监控默认就是开启的：

- `metrics.enabled=true`
- `metrics.serviceMonitor.enabled=true`

默认行为：

- 自动暴露 MinIO metrics
- 自动创建 `ServiceMonitor`
- 自动带上 `monitoring.archinfra.io/stack=default`

如果集群里没有 `ServiceMonitor` CRD，安装器会自动降级：

- 保留 metrics
- 跳过 `ServiceMonitor`

不会因为 Prometheus Operator 没装好就把 MinIO 整体安装弄失败。

## 快速开始

### 1. 看帮助

```bash
./minio-cluster-installer-amd64.run --help
./minio-cluster-installer-amd64.run help
```

### 2. 用默认参数安装

```bash
./minio-cluster-installer-amd64.run install -y
```

### 3. 查看状态

```bash
./minio-cluster-installer-amd64.run status -n aict
```

### 4. 卸载

```bash
./minio-cluster-installer-amd64.run uninstall -n aict -y
```

## 常见使用场景

### 场景 1：直接用默认值安装

```bash
./minio-cluster-installer-amd64.run install -y
```

### 场景 2：显式指定 AK/SK

```bash
./minio-cluster-installer-amd64.run install \
  --access-key 'minioadmin' \
  --secret-key 'StrongMinIO@2026' \
  -y
```

### 场景 3：改成 ClusterIP，不暴露 NodePort

```bash
./minio-cluster-installer-amd64.run install \
  --service-type ClusterIP \
  --console-service-type ClusterIP \
  -y
```

### 场景 4：保留 NodePort，但显式指定端口

```bash
./minio-cluster-installer-amd64.run install \
  --api-node-port 30093 \
  --console-node-port 30092 \
  -y
```

### 场景 5：关闭 Console

```bash
./minio-cluster-installer-amd64.run install \
  --disable-console \
  -y
```

### 场景 6：关闭监控

```bash
./minio-cluster-installer-amd64.run install \
  --disable-metrics \
  --disable-servicemonitor \
  -y
```

### 场景 7：目标仓库已存在镜像

```bash
./minio-cluster-installer-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --skip-image-prepare \
  -y
```

## 自定义参数怎么处理

这套安装器已经显式暴露了大部分常用参数，例如：

- `--mode`
- `--replicas`
- `--drives-per-node`
- `--access-key`
- `--secret-key`
- `--storage-class`
- `--storage-size`
- `--service-type`
- `--api-node-port`
- `--console-service-type`
- `--console-node-port`
- `--enable-metrics`
- `--enable-servicemonitor`
- `--minio-request-cpu`
- `--minio-request-mem`
- `--minio-limit-cpu`
- `--minio-limit-mem`
- `--console-request-cpu`
- `--console-request-mem`
- `--console-limit-cpu`
- `--console-limit-mem`
- `--mc-request-cpu`
- `--mc-request-mem`
- `--mc-limit-cpu`
- `--mc-limit-mem`

通用建议是：

- 常用运维场景优先使用安装器参数
- 特别细的 chart 定制，按需在仓库里继续维护 `values.yaml` 或安装器逻辑

## 给新维护者和 AI 的执行规约

如果你把安装包和 README 放到服务器上，让一个没有背景信息的人或 AI 去执行，建议把下面这些规则视为默认策略。

### 默认优先策略

没有额外约束时，优先使用：

- namespace: `aict`
- release name: `minio`
- mode: `distributed`
- replicas: `4`
- storage class: `nfs`
- metrics: `true`
- ServiceMonitor: `true`
- 如果是生产环境，显式传入新的 `--access-key` / `--secret-key`

### 成功标准

可以把这些看作安装成功信号：

- 4 个 MinIO 数据节点全部 `Running`
- API Service 存在
- Console Service 存在
- PVC 全部 `Bound`
- 如果集群支持 `ServiceMonitor`，则 MinIO 对应 `ServiceMonitor` 存在

### 失败信号

- Pod 长时间 `Pending`
- Pod `CrashLoopBackOff`
- PVC 长时间未绑定
- `ServiceMonitor` 期望开启但没有创建
- Console 可访问但 API 不可访问

### 操作建议

- 先确认 `StorageClass` 正常供卷
- 再执行安装
- 如果目标仓库已有镜像，优先使用 `--skip-image-prepare`
- 如果是演示环境，可沿用默认 AK/SK；生产环境必须改掉

## 常见排障命令

```bash
./minio-cluster-installer-amd64.run status -n aict
kubectl get pods,svc,pvc -n aict
kubectl get servicemonitor -A | grep minio
kubectl describe pod -n aict minio-0
kubectl logs -n aict minio-0
```

## 仓库结构

- `build.sh`
  多架构离线包构建入口
- `install.sh`
  自解包安装器模板
- `images/image.json`
  多架构镜像清单
- `charts/minio`
  vendored Helm chart
- `.github/workflows/build-offline-installer.yml`
  GitHub Actions 构建与发布流程

## GitHub Actions 与发布

推送到 `main` / `master`：

- 构建 `amd64` / `arm64` 安装包
- 上传构建产物

推送 `v*` tag：

- 构建双架构离线包
- 发布 GitHub Release
- 上传 `.run` 和 `.sha256`

## 说明

- 这套仓库保留了你原来设定的默认业务参数
- 运行时不要求目标机器安装 `jq`
- `ServiceMonitor` 缺失时会自动降级，不会影响 MinIO 主流程安装
