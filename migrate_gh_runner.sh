#!/usr/bin/env bash
set -euo pipefail

ORG_URL="https://github.com/dianma365"
RUNNER_USER="ghrunner"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 必须用 root 运行："
  echo '   TOKEN="xxxxx" bash migrate_gh_runner.sh'
  exit 1
fi

RUNNER_TOKEN="${TOKEN:-}"
if [ -z "$RUNNER_TOKEN" ]; then
  echo "❌ 环境变量 TOKEN 为空"
  echo '   用法：TOKEN="xxxxx" bash migrate_gh_runner.sh'
  exit 1
fi

if [ ! -d "$RUNNER_DIR" ]; then
  echo "❌ Runner 目录不存在: $RUNNER_DIR"
  exit 1
fi

echo "==> [root] 停止并卸载旧服务..."
if [ -f "${RUNNER_DIR}/svc.sh" ]; then
  ( cd "${RUNNER_DIR}" && ./svc.sh stop || true )
  ( cd "${RUNNER_DIR}" && ./svc.sh uninstall || true )
fi

echo "==> [ghrunner] 读取旧名称并重新注册到组织..."

export ORG_URL RUNNER_DIR RUNNER_TOKEN

su "${RUNNER_USER}" << 'EOF'
set -euo pipefail

cd "${RUNNER_DIR}"

echo "   - 尝试从 .runner / .runner_migrated 读取旧名称..."

OLD_NAME=""

if [ -f ".runner" ]; then
  OLD_NAME="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' .runner | head -n1 || true)"
elif [ -f ".runner_migrated" ]; then
  OLD_NAME="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' .runner_migrated | head -n1 || true)"
fi

if [ -z "$OLD_NAME" ]; then
  echo "❌ 无法自动从 .runner 或 .runner_migrated 解析原名称"
  echo "   这台机器需要你手动指定名称："
  echo "   步骤："
  echo "     su ghrunner"
  echo "     cd ${RUNNER_DIR}"
  echo '     rm -f .runner .runner_migrated .credentials .credentials_rsaparams .runner.env'
  echo '     ./config.sh --url ${ORG_URL} --token <TOKEN> --name "<原来的完整名称>" --runnergroup Default --labels "self-hosted,linux,x64" --unattended'
  exit 1
fi

echo "   ✅ 旧名称为: $OLD_NAME"
echo "   - 删除本地旧配置文件(.runner / .runner_migrated / .credentials*)..."

rm -f .runner .runner_migrated .credentials .credentials_rsaparams .runner.env || true

echo "   - 以旧名称重新注册到组织: ${ORG_URL} ..."
./config.sh \
  --url "${ORG_URL}" \
  --token "${RUNNER_TOKEN}" \
  --name "${OLD_NAME}" \
  --runnergroup "Default" \
  --labels "self-hosted,linux,x64" \
  --unattended

echo "   ✅ config.sh 完成"
EOF

echo "==> [root] 安装并启动服务..."
cd "${RUNNER_DIR}"
./svc.sh install || true
./svc.sh start

echo
echo "🎉 迁移脚本执行完毕（如中途报 ❌ 无法解析旧名称，那一台需要你手动处理）"
