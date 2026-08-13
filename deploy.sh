#!/usr/bin/env bash
#
# chatgpt-web-ui 一键部署脚本
#
# 功能(按顺序执行):
#   1. 拉取仓库更新(git pull,更新 compose 文件等)
#   2. 拉取最新镜像(docker compose pull)
#   3. 重建并启动容器(docker compose up -d)
#   4. 清理未使用的旧镜像(docker image prune -f)
#   5. 健康检查验证(/healthz)
#
# 用法:
#   ./deploy.sh                       # 完整部署(默认)
#   ./deploy.sh --no-pull             # 跳过 git pull,仅更新镜像并重启
#   ./deploy.sh --skip-healthcheck    # 跳过健康检查验证
#   ./deploy.sh --help                # 查看帮助
#
set -euo pipefail

# ---------- 输出辅助 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------- 参数解析 ----------
DO_GIT_PULL=true
DO_HEALTHCHECK=true

for arg in "$@"; do
  case "$arg" in
    --no-pull)          DO_GIT_PULL=false ;;
    --skip-healthcheck) DO_HEALTHCHECK=false ;;
    -h|--help)
      echo "用法: ./deploy.sh [--no-pull] [--skip-healthcheck]"
      exit 0
      ;;
    *) warn "未知参数: $arg(已忽略)" ;;
  esac
done

# ---------- 前置检查 ----------
cd "$(dirname "$0")"   # 保证从任意路径执行都定位到脚本所在目录

if ! command -v docker >/dev/null 2>&1; then
  error "未找到 docker 命令,请先安装 Docker"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  error "未找到 docker compose 插件,请安装 Docker Compose v2"
  exit 1
fi

# ---------- 1. 拉取仓库更新 ----------
if [ "$DO_GIT_PULL" = true ]; then
  if [ -d .git ]; then
    info "拉取仓库更新(git pull)..."
    git pull --ff-only
  else
    warn "未检测到 .git 目录,跳过 git pull"
  fi
else
  info "已跳过 git pull(--no-pull)"
fi

# ---------- 2. 拉取最新镜像 ----------
info "拉取最新镜像(docker compose pull)..."
docker compose pull

# ---------- 3. 重建并启动容器 ----------
info "重建并启动容器(docker compose up -d)..."
docker compose up -d

# ---------- 4. 清理旧镜像 ----------
info "清理未使用的旧镜像(docker image prune)..."
docker image prune -f

# ---------- 5. 健康检查验证 ----------
if [ "$DO_HEALTHCHECK" = true ]; then
  if ! command -v curl >/dev/null 2>&1; then
    warn "未找到 curl 命令,跳过健康检查"
  else
    # 从 compose 实际映射获取宿主机端口,失败时回退到 8000
    HOST_PORT=$(docker compose port chatgpt-web-ui 80 2>/dev/null | sed 's/.*://' || true)
    if [ -z "$HOST_PORT" ]; then
      HOST_PORT=$(sed -n 's/^[[:space:]]*-[[:space:]]*"\{0,1\}\([0-9]*\):80"/\1/p' docker-compose.yml | head -1)
    fi
    HOST_PORT="${HOST_PORT:-8000}"

    URL="http://127.0.0.1:${HOST_PORT}/healthz"
    info "健康检查: 探测 $URL ..."
    for i in $(seq 1 10); do
      if curl -fsS "$URL" >/dev/null 2>&1; then
        info "健康检查通过 ✅"
        break
      fi
      if [ "$i" -eq 10 ]; then
        error "健康检查失败:$URL 无法访问"
        error "请查看容器日志: docker compose logs -f chatgpt-web-ui"
        exit 1
      fi
      sleep 3
    done
  fi
else
  info "已跳过健康检查(--skip-healthcheck)"
fi

info "部署完成 🎉 访问 http://<服务器IP>:${HOST_PORT:-8000}"
