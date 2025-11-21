#!/usr/bin/env bash
set -euo pipefail

ORG_URL="https://github.com/dianma365"
RUNNER_USER="ghrunner"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 必须用 root 运行：TOKEN=... NAME=... bash migrate_gh_runner_simple.sh"
  exit 1
fi

TOKEN="${TOKEN:-}"
NAME="${NAME:-}"

if [ -z "$TOKEN" ] || [ -z "$NAME" ]; then
  echo "❌ 必须提供 TOKEN 和 NAME 环境变量"
  echo '   例：TOKEN="xxx" NAME="singapore-2-xxx-Ubuntu20" bash migrate_gh_runner_simple.sh'
  exit 1
fi

if [ ! -d "$RUNNER_DIR" ]; then
  echo "❌ Runner 目录不存在: $RUNNER_DIR"
  exit 1
fi

echo "==> [root] 停旧服务并删掉旧 service（如果有）..."
if ls /etc/systemd/system/actions.runner.*.service >/dev/null 2>&1; then
  for svc in /etc/systemd/system/actions.runner.*.service; do
    [ -e "$svc" ] || continue
    systemctl stop "$(basename "$svc")" || true
    systemctl disable "$(basename "$svc")" || true
    rm -f "$svc"
  done
  systemctl daemon-reload || true
fi

echo "==> [ghrunner] 清理旧配置并重新注册..."

sudo -u "$RUNNER_USER" bash -c "
  set -euo pipefail
  cd '$RUNNER_DIR'
  rm -f .runner .runner_migrated .credentials .credentials_rsaparams .runner.env || true
  ./config.sh \
    --url '$ORG_URL' \
    --token '$TOKEN' \
    --name '$NAME' \
    --runnergroup 'Default' \
    --labels 'self-hosted,linux,x64' \
    --unattended
"

echo "==> [root] 安装并启动新 service..."
cd "$RUNNER_DIR"
./svc.sh install || true
./svc.sh start || true

echo
echo "🎉 完成：Runner 名称 = $NAME"
