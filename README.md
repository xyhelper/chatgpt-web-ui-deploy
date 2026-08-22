# chatgpt-web-ui-deploy

[`xyhelper/chatgpt-web-ui`](https://github.com/xyhelper/chatgpt-web-ui) 的 Docker Compose 生产部署仓库。

> ⚠️ **上游项目为闭源**:`xyhelper/chatgpt-web-ui` 仓库不公开应用源码,仅以 Docker 镜像形式分发。

本仓库仅包含部署相关文件(`docker-compose.yml` 编排 + `deploy.sh` 部署脚本),应用本体以镜像 `ghcr.io/xyhelper/chatgpt-web-ui:latest` 形式从 GHCR 拉取,不包含源码。

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

### 3. 部署脚本(推荐)

```bash
./deploy.sh
```

脚本仅做三件事:**拉取最新镜像(`pull`)→ 重建并启动容器(`up -d --remove-orphans`,同时清理孤儿容器)→ 清理不再使用的历史版本镜像(`image prune -f`)**,不执行 `git pull`,不会覆盖你修改过的本地文件(如 `docker-compose.yml` 中的 `UPSTREAM_URL`),并自动适配新旧 compose 命令。

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
| `CLIENT_MAX_BODY_SIZE` | `512MB` | 客户端请求体(含文件上传)大小上限。值可为纯数字(字节)或带 `KB/MB/GB` 后缀(如 `100MB`、`1.5GB`),设为 `0` 不限制。GoFrame 默认仅 8MB,会在请求进入 handler 前用 MaxBytesReader 包装 Body,超过即读取报错;本服务 `PUT /files` 的文件上传转发依赖此值放宽(见上游 `config.ClientMaxBodySize`) |
| `UPSTREAM_URL` | `https://dev-chatgpt.xyhelper.cn` | 上游 API 服务地址,所有 `/backend-api/*` 等请求反向代理的目标 |
| `LOGIN_URL` | `/auth/uilogin` | 未登录(无 accessToken)时跳转的登录地址。**share 模式建议设置为 `/list`**(车队列表页):用户未登录时先看到车队列表,点击车队进入登录,登录后回到聊天页;mirror 模式(默认)为 `/auth/uilogin`(输入 access token 的登录页) |
| `SHOW_WORKSPACE` | `true` | 是否显示工作区域(聊天/工作切换器)。`true` 按账户结构自动判断,`false` 强制隐藏 |
| `TEMPLATE_VERSION` | 自动发现 | 固定页面模板 build 版本(如 `prod-xxx`)。一般无需配置,默认自动发现 `tpl/.current` 指向的最新版本。若显式指定了镜像内不存在的版本,启动时会尝试从 `https://github.com/oaistatic/<版本>` 自动克隆(见[模板版本缺失时自动克隆](#模板版本缺失时自动克隆)) |
| `TURNSTILE_SITE_KEY` | 空 | 自定义 Cloudflare Turnstile 站点 key。与 `TURNSTILE_SECRET_KEY` 同时配置才启用:前端(经 xy.js 劫持 turnstile.render)用自定义 key 渲染,后端 finalize 调 siteverify 真实验证,不匹配时 conversation 校验返回 403(见上游 `config.TurnstileEnabled`)。不配置则沿用模板内置官方 key,后端仅记录提交状态不真实验证 |
| `TURNSTILE_SECRET_KEY` | 空 | Turnstile 站点 secret key,须与 `TURNSTILE_SITE_KEY` 成对配置 |
| `PROOF_OF_WORK_ENABLED` | `false` | 是否启用 Proof of Work 挑战(前端哈希计算)。默认关闭:前端不计算、不提交 proofofwork,请求零额外开销;开启后 prepare 下发 seed/difficulty、finalize 校验哈希,失败时 conversation 统一返回 403 `chat_requirements_validation_failed`(见上游 `config.ProofOfWorkEnabled`) |
| `CHAT_REQ_GRACE_PERIOD` | `5m` | f/conversation 校验启动宽限期:进程刚启动的一段时间内跳过 `FConversationCheck` 全部校验直接转发上游,避免重启/部署后浏览器残留的旧 prepare/finalize token 导致上线瞬间大量 403(见上游 `config.ChatReqGracePeriod`)。值支持纯数字(单位:秒)或 Go duration 格式(`5m` / `300s` / `1h`);设为 `0` 表示不启用宽限期(启动即恢复完整校验) |
| `CDN_URLS_TTL` | `5m` | `/sw.js` 预缓存清单缓存有效期(见上游 `config.CdnUrlsTTL`、`ui.listCdnUrls`)。`/sw.js` 响应为 `no-cache`,每次页面刷新浏览器都会回源请求,服务端遍历模板 `cdn/` 目录生成预缓存清单,短时缓存避免高频刷新(多用户放大)下的重复读盘;热更新新增文件最多延迟 TTL 进入新清单并触发浏览器 SW 更新。值支持纯数字(单位:秒)或 Go duration 格式(`5m` / `300s` / `1h`);设为 `0` 表示禁用缓存(每次请求都重新扫描目录) |
| `RUN_MODE` | `mirror` | 运行模式:`mirror` 镜像模式(默认),完整代理上游、保持与上游一致的页面与接口行为;`share` 分享模式,无真实 JWT,登录页用 usertoken 作为用户名,由后端签发自签 access token(见 `FAKE_TOKEN_SECRET`),配合上游 gfsessionid 登录态使用。仅 share 模式会加载 `list.js`(车队列表页相关逻辑) |
| `FAKE_TOKEN_SECRET` | 默认内置值 | 自签 access token 的签名密钥(HS256),**仅 `RUN_MODE=share` 时使用**:登录页用 usertoken 作为用户名,后端 `POST /auth/fake-token` 签发带 `src:"local-fake"` 标记的假 accessToken,`renderPage` 据此判断登录态/显示用户名并验签识别伪造。**生产环境务必配置独立随机密钥**(默认值可被伪造) |

> **注意**:`UPSTREAM_URL` 在示例 compose 中为占位地址 `https://your-upstream.example.com`,注释标注为**必填**,**部署前请务必替换**为你自己的上游 API 地址,否则页面请求会全部打到无效地址。

### 模板版本缺失时自动克隆

镜像内置了默认的页面模板,一般无需任何配置即可直接使用。

若通过 `TEMPLATE_VERSION` 显式指定了一个**镜像内不存在**的模板版本,服务启动时会自动尝试从 `https://github.com/oaistatic/<版本>` 克隆该版本模板到容器内:

- **克隆成功**:自动使用该版本模板渲染页面
- **克隆失败**:启动日志会打印相关提示(如仓库不存在、网络不可达、未安装 git 等),此时请检查版本号是否正确、容器能否访问 `github.com`

> 自动克隆需要容器能访问 `github.com`,且目标版本已发布到 `oaistatic` 组织(由上游 `publish-template.sh` 发布)。普通使用场景无需配置 `TEMPLATE_VERSION`,直接使用镜像内置默认模板即可。

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

## 部署脚本(deploy.sh)

仓库提供 `deploy.sh` 部署脚本,仅执行三步:

1. 拉取最新镜像(`docker compose pull`)
2. 重建并启动容器(`docker compose up -d --remove-orphans`)
3. 清理不再使用的历史版本镜像(`docker image prune -f`)

```bash
./deploy.sh
```

> **新旧 Compose 命令自动适配**:脚本会优先使用新版 `docker compose`(Compose v2 插件),不存在时自动回退到旧版独立命令 `docker-compose`(Compose v1),两种环境均可直接使用。
>
> `--remove-orphans` 会一并清理 compose 文件中已不存在的孤儿容器(如修改 compose 删除某服务后,旧容器不会残留),不影响当前服务及容器内数据。
>
> `docker image prune -f` 只清理未被任何容器引用的镜像(悬空镜像 + 旧版本镜像),不影响当前运行中镜像,可放心使用。

## 更新与升级

本服务无状态,升级只需拉取新镜像并重建容器:

```bash
docker compose pull
docker compose up -d
```

或直接使用部署脚本(自动适配新旧 compose 命令,并自动清理不再使用的历史版本镜像):

```bash
./deploy.sh
```

如需手动清理旧镜像:

```bash
docker image prune -f
```

## 自定义页面与脚本(可选)

服务内置以下可自定义的静态资源,均位于容器内 `/app/resource/public/`。推荐使用**单文件绑定挂载**覆盖:只遮蔽该文件、不影响镜像内其余资源,升级镜像时挂载仍然保留,是最安全的自定义方式。

| 可自定义文件 | 容器内路径 | 说明 |
| --- | --- | --- |
| 自定义脚本 | `/app/resource/public/custom.js` | **每个页面都会加载**(jquery 之后、xy.js 之前,URL 带时间戳防缓存),适合注入样式、拦截请求、改 DOM、接第三方统计 |
| 登录页 | `/app/resource/public/auth/login/index.html` | share 模式登录页(输入 usertoken,经 `/auth/logintoken` 校验),单文件自包含(内联 CSS/JS)。mirror 模式(默认)登录页为 `/auth/uilogin`(输入 access token) |
| 车队列表页 | `/app/resource/public/list/index.html` | 车队列表页 `/list`,仅 `RUN_MODE=share` 使用,单文件自包含 |
| 列表页逻辑脚本 | `/app/resource/public/list.js` | share 模式**每个页面**都会加载的车队列表逻辑(URL 带时间戳),mirror 模式不加载 |
| 全局脚本 | `/app/resource/public/xy.js` | 全局逻辑,每个页面加载(URL 带时间戳) |

> 挂载前可先执行 `docker compose cp chatgpt-web-ui:/app/resource/public/<文件> ./` 把镜像内置文件复制到宿主机作为修改模板。

### 1. 自定义 custom.js(推荐)

`custom.js` 是专门预留的自定义代码入口,每个页面都会加载,适合做纯前端增强(改样式、调行为、接统计),无需修改任何 Go 代码。

1. 复制内置模板到宿主机:

   ```bash
   docker compose cp chatgpt-web-ui:/app/resource/public/custom.js ./custom.js
   ```

2. 编辑 `./custom.js`,在文件内编写你的自定义代码(内置模板自带使用说明注释与示例):

   ```js
   (function () {
     "use strict";
     // ===== 在此下方编写你的自定义代码 =====
     // 示例:页面加载完成后打印日志
     console.log("[custom.js] loaded");
     // ===== 自定义代码结束 =====
   })();
   ```

3. 在 `docker-compose.yml` 中挂载:

   ```yaml
   volumes:
     - ./custom.js:/app/resource/public/custom.js:ro
   ```

4. 重启生效并验证:

   ```bash
   docker compose up -d
   ```

> 加载 URL 带时间戳(`?v=...`),之后每次修改只需刷新页面即可立即生效,无需清浏览器缓存、无需重启容器。

### 2. 自定义登录页

share 模式的登录页是 `/auth/login`(容器内 `/app/resource/public/auth/login/index.html`),单文件自包含(内联 CSS/JS),直接挂载单文件即可完整自定义(mirror 模式默认登录页为 `/auth/uilogin`,见"环境变量一览"的 `LOGIN_URL`):

1. 复制内置登录页作为模板:

   ```bash
   mkdir -p login
   docker compose cp chatgpt-web-ui:/app/resource/public/auth/login/index.html ./login/index.html
   ```

2. 按需修改 `./login/index.html`(改样式、文案、提交逻辑等),然后挂载:

   ```yaml
   volumes:
     - ./login/index.html:/app/resource/public/auth/login/index.html:ro
   ```

3. `docker compose up -d` 重建生效。

> **注意(share 模式)**:share 模式的登录页与后端接口配合工作——提交 usertoken 后经 `/auth/logintoken` 校验登录,再调 `/auth/fake-token` 签发自签 access token(见 `FAKE_TOKEN_SECRET`)。若自定义登录页改动了表单提交逻辑,需保持与内置页一致(参考内置 `login/index.html` 的 `doLogin` 流程),否则无法登录。

### 3. 自定义车队列表页(/list)

`/list` 是 share 模式的车队列表页(容器内 `/app/resource/public/list/index.html`),单文件自包含,同样支持单文件挂载:

1. 复制内置列表页作为模板:

   ```bash
   mkdir -p list
   docker compose cp chatgpt-web-ui:/app/resource/public/list/index.html ./list/index.html
   ```

2. 修改后挂载:

   ```yaml
   volumes:
     - ./list/index.html:/app/resource/public/list/index.html:ro
   ```

3. `docker compose up -d` 重建生效。

> 列表页外观(HTML/CSS)改 `list/index.html` 即可;若想改**行为**(如车队列表拉取、通知拦截逻辑),可修改 `/app/resource/public/list.js` 并挂载:
>
> ```yaml
> volumes:
>   - ./list.js:/app/resource/public/list.js:ro
> ```

### 4. 修改后如何生效

- **JS 文件**(`custom.js` / `list.js` / `xy.js`):加载 URL 带时间戳,静态资源实时读盘,改完**刷新页面**即生效,无浏览器缓存问题;
- **HTML 页面**(登录页 / list 页):修改后刷新页面即可,若浏览器有缓存可强刷(`Ctrl+F5`);页面本身请求的仍是静态文件,同样无需重启容器;
- **修改 `docker-compose.yml`**(如新增/调整挂载)后需 `docker compose up -d` 重建生效。

> ⚠️ **挂载遮蔽警告**:绑定挂载会遮蔽镜像内同名路径的内容。上文推荐的单文件挂载(如 `./custom.js:/app/resource/public/custom.js`)只遮蔽该文件,**安全**;但**切勿整目录挂载** `resource/public` 或 `resource/template/tpl`(除非宿主机目录已含完整资源),否则镜像内置资源被遮蔽、页面模板丢失无法渲染(见下方 FAQ)。

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
  LOGIN_URL: "/list"   # share 模式建议设置为 /list(车队列表页)
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

