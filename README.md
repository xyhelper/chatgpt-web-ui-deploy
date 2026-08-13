# chatgpt-web-ui-deploy

[`xyhelper/chatgpt-web-ui`](https://github.com/xyhelper/chatgpt-web-ui) 的 Docker Compose 生产部署仓库。

本仓库仅包含部署相关文件(`docker-compose.yml` 编排 + `deploy.sh` 一键部署脚本),应用本体以镜像 `ghcr.io/xyhelper/chatgpt-web-ui:latest` 形式从 GHCR 拉取,不包含源码。

## 特性

- **开箱即用**:一条命令启动,镜像内置完整页面模板与静态资源
- **无状态**:登录态等数据存于浏览器 cookie,**无需持久化卷**,升级零迁移
- **配置灵活**:支持环境变量与挂载 `config.yaml` 两种方式
- **自带健康检查**:探测独立端点 `/healthz`,不渲染页面、不请求上游、不依赖登录态
- **反向代理内置**:`/backend-api/*`、`/v1`、`/realtime/*`、`/public-api/*` 等请求自动代理到上游 API

## 快速开始

### 1. 获取部署文件

```bash
git clone https://github.com/xyhelper/chatgpt-web-ui-deploy.git
cd chatgpt-web-ui-deploy
```

> 只需 `docker-compose.yml` 与 `deploy.sh` 两个文件,复制到你的服务器即可。

### 2. 修改配置(必填)

编辑 `docker-compose.yml`,把 `UPSTREAM_URL` 占位地址替换为你自己的上游 API 地址:

```yaml
environment:
  UPSTREAM_URL: "https://your-upstream.example.com"   # ← 改为你的上游地址
```

> `UPSTREAM_URL` 为**必填项**,不修改则页面接口会全部请求到无效地址。其余配置均有合理默认值,一般无需改动。详见[配置说明](#配置说明)。

### 3. 一键部署(推荐)

```bash
./deploy.sh
```

脚本自动完成:**拉取仓库更新 → 拉取最新镜像 → 启动容器 → 清理旧镜像 → 健康检查**。

部署完成后访问 <http://服务器IP:8000> 即可。

### 或手动启动

```bash
docker compose up -d
```

### 验证服务状态

```bash
# 查看容器状态与日志
docker compose ps
docker compose logs -f

# 健康检查(应返回 200 + "ok")
curl -i http://127.0.0.1:8000/healthz
```

## 配置说明

### 配置优先级

```
config.yaml(挂载) > 环境变量 > 镜像内置默认值
```

- **挂载的 `config.yaml`** 优先级最高,可覆盖全部配置
- **环境变量**其次,便于不改文件快速调整
- **镜像内置默认值**兜底(见上游 `config/config.go`)

### 环境变量一览

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PORT` | `80` | web 服务监听端口(**容器内**端口,需与 `ports` 映射保持一致) |
| `UPSTREAM_URL` | `https://dev-chatgpt.xyhelper.cn` | 上游 API 服务地址,所有 `/backend-api/*` 等请求反向代理的目标 |
| `LOGIN_URL` | `/auth/login` | 未登录(无 accessToken)时跳转的登录地址 |
| `SHOW_WORKSPACE` | `true` | 是否显示工作区域(聊天/工作切换器)。`true` 按账户结构自动判断,`false` 强制隐藏 |
| `TEMPLATE_VERSION` | 自动发现 | 固定页面模板 build 版本(如 `prod-xxx`)。一般无需配置,默认自动发现 `tpl/.current` 指向的最新版本 |

> **注意**:`UPSTREAM_URL` 在示例 compose 中为占位地址 `https://your-upstream.example.com`,注释标注为**必填**,**部署前请务必替换**为你自己的上游 API 地址,否则页面请求会全部打到无效地址。

### 自定义 config.yaml(可选)

如果需要更精细的配置管理,可挂载自定义配置文件:

1. 从容器内复制默认配置(镜像内置 `config.yaml.sample` 已复制为 `/app/config.yaml`):

   ```bash
   docker compose cp chatgpt-web-ui:/app/config.yaml ./config.yaml
   ```

2. 按需修改 `./config.yaml`,然后在 `docker-compose.yml` 中取消注释:

   ```yaml
   volumes:
     - ./config.yaml:/app/config.yaml:ro
   ```

3. 重启生效:

   ```bash
   docker compose up -d
   ```

### 修改端口

默认映射为宿主机 `8000` → 容器内 `80`。如需修改宿主机端口:

```yaml
ports:
  - "8080:80"   # 宿主机 8080 -> 容器内 80
```

如需修改容器内端口,需同步修改:

- `environment.PORT`(示例为 `80`)
- 健康检查 URL 中的端口(`http://127.0.0.1:80/healthz`)

## 健康检查

服务内置独立健康检查端点 `/healthz`:

- 返回 `200` + `"ok"`
- 不渲染页面、不请求上游、不依赖登录态

因此它适合接入 Docker `healthcheck`、负载均衡器或 Kubernetes 探针。**不应**使用 `/` 作为探针路径——该路径走完整页面渲染流程,无法反映服务真实存活状态。

## 一键部署脚本(deploy.sh)

仓库提供 `deploy.sh` 一键部署脚本,自动完成**拉取更新 → 部署**全流程:

1. 拉取仓库更新(`git pull`,更新 compose 文件等)
2. 拉取最新镜像(`docker compose pull`)
3. 重建并启动容器(`docker compose up -d`)
4. 清理未使用的旧镜像(`docker image prune -f`)
5. 健康检查验证(`/healthz`)

```bash
./deploy.sh                       # 完整部署(默认)
./deploy.sh --no-pull             # 跳过 git pull,仅更新镜像并重启
./deploy.sh --skip-healthcheck    # 跳过健康检查验证
```

> 脚本会自动解析 compose 中的宿主端口并探测 `http://127.0.0.1:<端口>/healthz` 验证服务可用性。
> 可直接配置到 crontab 实现定时自动更新部署。

## 更新与升级

本服务无状态,升级只需拉取新镜像并重建容器:

```bash
docker compose pull
docker compose up -d
```

如需清理旧镜像:

```bash
docker image prune
```

> 使用一键部署脚本可自动完成以上全部步骤,见[一键部署脚本](#一键部署脚本deploysh)。

## 常见问题(FAQ)

### 挂载目录后页面空白/模板丢失

**卷/绑定挂载会遮蔽镜像内同名路径的内容**(镜像内打包的资源在挂载后不可见)。

若挂载 `resource/template/tpl`、`resource/public` 等目录,须先确保宿主机目录包含完整资源(如从镜像 `COPY` 出来),否则页面模板丢失、无法渲染。

### 页面能打开但接口全部报错

多半是 `UPSTREAM_URL` 仍是占位地址或指向了不可达的上游。检查:

```bash
docker compose logs chatgpt-web-ui
```

### 未登录时跳转地址不对

通过 `LOGIN_URL` 环境变量指定,例如:

```yaml
environment:
  LOGIN_URL: "/auth/login"
```

### 想隐藏工作区域(聊天/工作切换器)

```yaml
environment:
  SHOW_WORKSPACE: "false"
```

### 端口被占用

修改 `ports` 的宿主机端口,或先停掉占用进程:

```bash
docker compose down
```

## 相关链接

- 上游项目: <https://github.com/xyhelper/chatgpt-web-ui>
- 镜像地址: `ghcr.io/xyhelper/chatgpt-web-ui:latest`

