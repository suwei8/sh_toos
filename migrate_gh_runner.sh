#!/usr/bin/env bash
set -euo pipefail

################################
# 固定配置（根据你的实际情况）
################################
ORG_URL="https://github.com/dianma365"
RUNNER_USER="ghrunner"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

################################
# 基本检查
################################
if [[ $EUID -ne 0 ]]; then
  echo "请用 root 或 sudo 运行（因为需要切换到 ghrunner 用户）"
  exit 1
fi

if [[ ! -d "${RUNNER_DIR}" ]]; then
  echo "Runner 目录不存在: ${RUNNER_DIR}"
  exit 1
fi

################################
# 获取 TOKEN
################################
read -rp "请输入【组织级 Runner TOKEN】：" RUNNER_TOKEN
if [[ -z "${RUNNER_TOKEN}" ]]; then
  echo "TOKEN 不能为空"
  exit 1
fi

################################
# 1. 停止旧 runner（以 ghrunner 身份）
################################
echo "==> 停止 runner 服务..."
sudo -u "${RUNNER_USER}" bash -lc "cd '${RUNNER_DIR}' && ./svc.sh stop || true"

################################
# 2. remove 原绑定
################################
echo "==> 解绑旧仓库 Runner..."
sudo -u "${RUNNER_USER}" bash -lc "
  cd '${RUNNER_DIR}' && \
  ./config.sh remove --unattended || true
"

################################
# 3. 重新绑定到新组织
################################
echo "==> 注册 Runner 到组织 ${ORG_URL} ..."
sudo -u "${RUNNER_USER}" bash -lc "
  cd '${RUNNER_DIR}' && \
  ./config.sh \
    --url '${ORG_URL}' \
    --token '${RUNNER_TOKEN}' \
    --unattended
"

################################
# 4. 重新安装 & 启动 svc
################################
echo '==> 重新安装并启动服务...'
sudo -u "${RUNNER_USER}" bash -lc "cd '${RUNNER_DIR}' && sudo ./svc.sh install || true"
sudo -u "${RUNNER_USER}" bash -lc "cd '${RUNNER_DIR}' && sudo ./svc.sh start"

echo
echo "🎉 完成迁移：Runner 已成功绑定到 ${ORG_URL}"
echo "   所有 dianma365 组织下的仓库都可以使用这台 Runner"
