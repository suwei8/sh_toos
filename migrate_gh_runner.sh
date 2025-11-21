#!/usr/bin/env bash
set -euo pipefail

ORG_URL="https://github.com/dianma365"
RUNNER_USER="ghrunner"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 必须用 root 运行：TOKEN=\"xxx\" bash migrate_gh_runner.sh"
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
  SERVICE_FILE="$(ls /etc/systemd/system/actions.runner.*.service 2>/dev/null | head -n1 || true)"
  if [ -n "$SERVICE_FILE" ]; then
    SVC_NAME="$(basename "$SERVICE_FILE")"
    systemctl stop "$SVC_NAME" || true
    systemctl disable "$SVC_NAME" || true
    rm -f "$SERVICE_FILE"
  fi
fi

systemctl daemon-reload || true

# 从旧 service 文件推 runner 名
OLD_NAME=""
if [ -n "${SERVICE_FILE:-}" ]; then
  # actions.runner.<org>.<runnername>.service
  OLD_NAME="$(basename "$SERVICE_FILE" | sed -E 's/actions\.runner\.[^.]+\.(.+)\.service/\1/')" || true
fi

export ORG_URL RUNNER_DIR RUNNER_TOKEN OLD_NAME

echo "==> [root] 切换到 ghrunner 执行 config..."

su "$RUNNER_USER" << 'EOF'
set -euo pipefail

cd "$RUNNER_DIR"

echo "   - 清理本地旧配置文件 (.runner / .runner_migrated / .credentials*)..."
rm -f .runner .runner_migrated .credentials .credentials_rsaparams .runner.env || true

echo "   - 解析原名称..."

FINAL_NAME=""

# 1. 优先用 root 通过 service 文件传进来的 OLD_NAME
if [ -n "${OLD_NAME:-}" ]; then
  FINAL_NAME="$OLD_NAME"
fi

# 2. 再看 .runner
if [ -z "$FINAL_NAME" ] && [ -f ".runner" ]; then
  FINAL_NAME="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' .runner | head -n1 || true)"
fi

# 3. 再看 .runner_migrated
if [ -z "$FINAL_NAME" ] && [ -f ".runner_migrated" ]; then
  FINAL_NAME="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' .runner_migrated | head -n1 || true)"
fi

if [ -z "$FINAL_NAME" ]; then
  echo "❌ 自动解析原名称失败："
  echo "   - 没有可用的 service 文件"
  echo "   - 也没有 .runner / .runner_migrated"
  echo "   这台机子已经彻底丢失名字，只能你手动指定。"
  exit 1
fi

echo "   ✅ 原名称：$FINAL_NAME"

echo "   - 第一次尝试执行 config.sh..."
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
  echo "   ⚠️ 第一次 config 失败，尝试自动 remove 再重试一次..."
  # 尝试清理本地“已配置”状态
  set +e
  ./config.sh remove || true
  rm -f .runner .runner_migrated .credentials .credentials_rsaparams .runner.env || true
  set -e

  echo "   - 第二次重试执行 config.sh..."
  ./config.sh \
    --url "$ORG_URL" \
    --token "$RUNNER_TOKEN" \
    --name "$FINAL_NAME" \
    --runnergroup "Default" \
    --labels "self-hosted,linux,x64" \
    --unattended
fi

echo "   ✅ ghrunner 下 config.sh 完成"
EOF

echo "==> [root] 安装并启动新服务..."
cd "$RUNNER_DIR"
./svc.sh install || true
./svc.sh start || true

echo
echo "🎉 迁移完成：Runner 已重新绑定到 $ORG_URL"
echo "   （如有极少数机器提示“自动解析原名称失败”，那台就只能手动指定名字）"
