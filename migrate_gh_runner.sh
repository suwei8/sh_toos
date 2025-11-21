#!/usr/bin/env bash
set -euo pipefail

# ===== 固定环境配置 =====
ORG_URL="https://github.com/dianma365"
RUNNER_USER="ghrunner"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

# ===== 必须 root 运行 =====
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 必须用 root 运行：sudo bash migrate_gh_runner.sh"
  exit 1
fi

# ===== 从环境变量拿 TOKEN =====
RUNNER_TOKEN="${TOKEN:-}"

if [ -z "$RUNNER_TOKEN" ]; then
  echo "❌ 没有检测到 TOKEN 环境变量"
  echo '用法示例：'
  echo 'TOKEN="xxxxx" bash migrate_gh_runner.sh'
  exit 1
fi

# ===== 检查目录 =====
if [ ! -d "$RUNNER_DIR" ]; then
  echo "❌ Runner 目录不存在: $RUNNER_DIR"
  exit 1
fi

echo "==> 1) root 停止并卸载旧服务（在 runner 目录下执行 svc.sh）..."
cd "$RUNNER_DIR"
if [ -f "./svc.sh" ]; then
  ./svc.sh stop || true
  ./svc.sh uninstall || true
fi

echo "==> 2) 用 ghrunner 读取原来的 runner 名称（.runner 里的 name 字段）..."
OLD_NAME="$(
  su - "$RUNNER_USER" -s /bin/bash -c "
    cd '$RUNNER_DIR' 2>/dev/null || exit 0
    if [ -f .runner ]; then
      sed -n 's/.*\"name\"[ ]*:[ ]*\"\\(.*\\)\".*/\\1/p' .runner | head -n1
    fi
  "
)"

if [ -z "$OLD_NAME" ]; then
  echo "⚠️ 找不到旧名称 (.runner 不存在或解析失败)，临时用 hostname 当名字"
  OLD_NAME="$(hostname)"
else
  echo "   旧名称为: $OLD_NAME"
fi

echo "==> 3) 用 ghrunner 删除本地旧配置文件 (.runner / .credentials 等)..."
su - "$RUNNER_USER" -s /bin/bash -c "
  cd '$RUNNER_DIR' || exit 0
  rm -f .runner .credentials .credentials_rsaparams .runner.env || true
"

echo "==> 4) 用 ghrunner 以原名称 [$OLD_NAME] 重新注册到组织（全程无交互）..."
su - "$RUNNER_USER" -s /bin/bash -c "
  cd '$RUNNER_DIR'
  ./config.sh \
    --url '$ORG_URL' \
    --token '$RUNNER_TOKEN' \
    --name '$OLD_NAME' \
    --runnergroup 'Default' \
    --labels 'self-hosted,linux,x64' \
    --unattended
"

echo "==> 5) root 重新安装并启动服务..."
cd "$RUNNER_DIR"
./svc.sh install || true
./svc.sh start

echo
echo "🎉 迁移完成：Runner 已绑定到 $ORG_URL，名称：$OLD_NAME"
