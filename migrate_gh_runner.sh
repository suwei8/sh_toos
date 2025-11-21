#!/usr/bin/env bash
set -euo pipefail

ORG_URL="https://github.com/dianma365"
RUNNER_USER="ghrunner"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 必须用 root 运行"
  exit 1
fi

RUNNER_TOKEN="${TOKEN:-}"
if [ -z "$RUNNER_TOKEN" ]; then
  echo "❌ 环境变量 TOKEN 为空"
  exit 1
fi

if [ ! -d "$RUNNER_DIR" ]; then
  echo "❌ Runner 目录不存在: $RUNNER_DIR"
  exit 1
fi

echo "==> [root] 停止并删除旧服务..."

SERVICE_FILE=""
if ls /etc/systemd/system/actions.runner.*.service >/dev/null 2>&1; then
  SERVICE_FILE="$(ls /etc/systemd/system/actions.runner.*.service | head -n1 || true)"
  if [ -n "$SERVICE_FILE" ]; then
    SVC_NAME="$(basename "$SERVICE_FILE")"
    systemctl stop "$SVC_NAME" || true
    systemctl disable "$SVC_NAME" || true
    rm -f "$SERVICE_FILE"
  fi
fi

systemctl daemon-reload || true

OLD_NAME=""
if [ -n "${SERVICE_FILE:-}" ]; then
  OLD_NAME="$(basename "$SERVICE_FILE" | sed -E 's/actions\.runner\.[^.]+\.(.+)\.service/\1/')" || true
fi

export ORG_URL RUNNER_DIR RUNNER_TOKEN OLD_NAME

echo "==> [root] 切换到 ghrunner 执行 config..."

su "$RUNNER_USER" << 'EOF'
set -euo pipefail

cd "$RUNNER_DIR"

rm -f .runner .runner_migrated .credentials .credentials_rsaparams .runner.env || true

FINAL_NAME="${OLD_NAME:-}"

# 自动解析失败 → 让用户输入
if [ -z "$FINAL_NAME" ]; then
  echo "⚠️  自动解析原名称失败"
  echo -n "👉 请输入这台机器原来的 Runner 完整名称: "
  read FINAL_NAME
fi

# 最终必须有名字
if [ -z "$FINAL_NAME" ]; then
  echo "❌ 你没有输入名称，无法继续"
  exit 1
fi

echo "   使用名称：$FINAL_NAME"

set +e
./config.sh \
  --url "$ORG_URL" \
  --token "$RUNNER_TOKEN" \
  --name "$FINAL_NAME" \
  --runnergroup "Default" \
  --labels "self-hosted,linux,x64" \
  --unattended
RC=$?
set -e

if [ $RC -ne 0 ]; then
  echo "⚠️ config 失败，尝试 remove 再重试"

  ./config.sh remove || true
  rm -f .runner .credentials .credentials_rsaparams .runner.env .runner_migrated || true

  ./config.sh \
    --url "$ORG_URL" \
    --token "$RUNNER_TOKEN" \
    --name "$FINAL_NAME" \
    --runnergroup "Default" \
    --labels "self-hosted,linux,x64" \
    --unattended
fi

echo "   ✅ 注册成功：$FINAL_NAME"
EOF

echo "==> [root] 安装并启动新服务..."
cd "$RUNNER_DIR"
./svc.sh install || true
./svc.sh start || true

echo
echo "🎉 完成：Runner 已迁移"
