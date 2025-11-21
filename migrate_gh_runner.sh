#!/usr/bin/env bash
set -euo pipefail

# ========= 固定配置 =========
ORG_URL="https://github.com/dianma365"
RUNNER_USER="ghrunner"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

# ========= 必须 root 运行 =========
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 必须用 root 运行：例如"
  echo '   TOKEN="xxxxx" sudo bash migrate_gh_runner.sh'
  exit 1
fi

# ========= 从环境变量拿 TOKEN =========
RUNNER_TOKEN="${TOKEN:-}"

if [ -z "$RUNNER_TOKEN" ]; then
  echo "❌ 没有检测到 TOKEN 环境变量 TOKEN"
  echo '用法示例：'
  echo '   TOKEN="xxxxx" bash migrate_gh_runner.sh'
  exit 1
fi

# ========= 检查 runner 目录 =========
if [ ! -d "$RUNNER_DIR" ]; then
  echo "❌ Runner 目录不存在: $RUNNER_DIR"
  exit 1
fi

echo "==> 1) root：进入 runner 目录并停止 / 卸载旧服务..."
cd "$RUNNER_DIR"

if [ -f "./svc.sh" ]; then
  ./svc.sh stop || true
  ./svc.sh uninstall || true
fi

echo "==> 2) su ghrunner：读取原来的名称、清理旧配置、重新 config 到组织..."

# 把变量传进 ghrunner 的环境，然后用 HEREDOC 进入完整登录 shell
RUNNER_TOKEN="$RUNNER_TOKEN" ORG_URL="$ORG_URL" RUNNER_DIR="$RUNNER_DIR" su "$RUNNER_USER" << 'EOF'
set -euo pipefail

cd "$RUNNER_DIR"

echo "   - 尝试从 .runner 中读取旧名称..."
OLD_NAME=""

if [ -f ".runner" ]; then
  OLD_NAME="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' .runner | head -n1 || true)"
fi

if [ -z "$OLD_NAME" ]; then
  echo "   ⚠️ .runner 不存在或没有 name 字段，使用 hostname 作为名称"
  OLD_NAME="$(hostname)"
else
  echo "   ✅ 旧名称为: $OLD_NAME"
fi

echo "   - 删除本地旧配置文件 .runner / .credentials* ..."
rm -f .runner .credentials .credentials_rsaparams .runner.env || true

echo "   - 使用原名称重新注册到组织：\$ORG_URL ..."
./config.sh \
  --url "\$ORG_URL" \
  --token "\$RUNNER_TOKEN" \
  --name "\$OLD_NAME" \
  --runnergroup "Default" \
  --labels "self-hosted,linux,x64" \
  --unattended

echo "   ✅ config.sh 执行完成（ghrunner 身份）"
EOF

echo "==> 3) root：重新安装并启动服务..."
cd "$RUNNER_DIR"
./svc.sh install || true
./svc.sh start

echo
echo "🎉 迁移完成：Runner 已绑定到 $ORG_URL"
echo "   名称：$OLD_NAME （如 .runner 还在则为原名称，丢失则为 hostname）"
