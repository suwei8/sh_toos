#!/usr/bin/env bash
set -euo pipefail

################################
# 固定配置（完全按你的环境）
################################
ORG_URL="https://github.com/dianma365"
RUNNER_USER="ghrunner"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

################################
# 获取 TOKEN（从环境变量注入）
################################
RUNNER_TOKEN="${TOKEN:-}"

if [[ -z "${RUNNER_TOKEN}" ]]; then
  echo "❌ 未检测到 TOKEN 环境变量"
  echo "请按以下格式运行："
  echo 'TOKEN="xxxx" bash migrate_gh_runner_final.sh'
  exit 1
fi

################################
# 检查 runner 目录
################################
if [[ ! -d "${RUNNER_DIR}" ]]; then
  echo "❌ 未找到 runner 目录: ${RUNNER_DIR}"
  exit 1
fi

################################
# 1. 停止旧服务
################################
echo "==> 停止 Runner 服务..."
sudo -u "${RUNNER_USER}" bash -lc "
  cd '${RUNNER_DIR}'
  ./svc.sh stop || true
"

################################
# 2. remove 旧绑定
################################
echo "==> 解绑旧 Runner..."
sudo -u "${RUNNER_USER}" bash -lc "
  cd '${RUNNER_DIR}'
  ./config.sh remove --unattended || true
"

################################
# 3. 注册到组织
################################
echo "==> 绑定到组织：${ORG_URL}"
sudo -u "${RUNNER_USER}" bash -lc "
  cd '${RUNNER_DIR}'
  ./config.sh \
    --url '${ORG_URL}' \
    --token '${RUNNER_TOKEN}' \
    --unattended
"

################################
# 4. 安装并启动 svc
################################
echo "==> 启动 Runner 服务..."
sudo -u "${RUNNER_USER}" bash -lc "
  cd '${RUNNER_DIR}'
  sudo ./svc.sh install || true
  sudo ./svc.sh start
"

echo
echo "🎉🎉🎉 迁移成功！！ Runner 已绑定到 ${ORG_URL}"
echo "所有 dianma365/* 仓库现在都可以使用这台 Runner ❤️"
