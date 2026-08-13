#!/usr/bin/env bash
#
# chatgpt-web-ui 简单部署脚本
#
# 仅执行:
#   1. 拉取最新镜像
#   2. 重建并启动容器(并清理孤儿容器)
#   3. 清理不再使用的历史版本镜像
#
# 用法:
#   ./deploy.sh            # 拉取最新镜像并启动容器
#   ./deploy.sh --help     # 查看帮助
#
set -euo pipefail

# ---------- 输出辅助 ----------
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------- 帮助 ----------
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<EOF
用法: ./deploy.sh

仅执行:
  1. docker compose pull                (拉取最新镜像)
  2. docker compose up -d --remove-orphans (重建并启动容器,并清理孤儿容器)
  3. docker image prune -f              (清理不再使用的历史版本镜像)
EOF
  exit 0
fi

# ---------- 前置检查:适配新旧 compose 命令 ----------
# 优先使用新版 `docker compose`(Docker Compose v2 插件);
# 不存在时回退到旧版独立命令 `docker-compose`(Compose v1)。
# 注意:两种写法对应不同的子命令集合,本脚本只用到两者均支持的
# `pull` / `up -d`,因此可安全适配。
cd "$(dirname "$0")"   # 保证从任意路径执行都定位到脚本所在目录

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  error "未找到 docker compose / docker-compose,请先安装 Docker Compose"
  exit 1
fi

info "使用命令: ${COMPOSE[*]}"

# ---------- 1. 拉取最新镜像 ----------
info "拉取最新镜像(${COMPOSE[*]} pull)..."
"${COMPOSE[@]}" pull

# ---------- 2. 重建并启动容器 ----------
# --remove-orphans:一并移除 compose 文件中已不存在的孤儿容器
# (如修改过 compose 删除某服务后,旧容器不会残留),且不影响容器内数据
info "重建并启动容器(${COMPOSE[*]} up -d --remove-orphans)..."
"${COMPOSE[@]}" up -d --remove-orphans

# ---------- 3. 清理不再使用的历史版本镜像 ----------
# 仅清理未被任何容器引用的镜像(悬空 + 旧版本),不影响当前运行中的镜像
info "清理不再使用的历史版本镜像(docker image prune -f)..."
docker image prune -f

info "完成 ✅"
