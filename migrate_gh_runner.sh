#!/usr/bin/env bash
set -euo pipefail

ORG_URL="https://github.com/dianma365"
RUNNER_USER="ghrunner"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

# 从环境变量拿 TOKEN
RUNNER_TOKEN="${TOKEN:-}"

if [[ -z "${RUNNER_TOKEN}" ]]; then
  echo "❌ 没有检测到 TOKEN 环境变量"
  echo '用法示例：'
  echo 'TOKEN="xxxxx" bash migrate_gh_runner.sh'
  exit 1
fi

if [[ ! -d "${RUNNER_DIR}" ]]; then
  echo "❌ Runner 目录不存在: ${RUNNER_DIR}"
  exit 1
fi

echo "==> 停止并卸载旧服务（root 调用 svc.sh）..."
if [[ -f "${RUNNER_DIR}/svc.sh" ]]; then
  sudo "${RUNNER_DIR}/svc.sh" stop || true
  sudo "${RUNNER_DIR}/svc.sh" uninstall || true
fi

echo "==> 用 ghrunner 读取原来的 runner 名称（.runner 中的 name 字段）..."
OLD_NAME="$(sudo -u "${RUNNER_USER}" bash -lc "
  cd '${RUNNER_DIR}' 2>/dev/null || exit 0
  if [[ -f .runner ]]; then
    sed -n 's/.*\"name\"[ ]*:[ ]*\"\\(.*\\)\".*/\\1/p' .runner | head -n1
  fi
")"

if [[ -z "${OLD_NAME}" ]]; then
  echo "⚠️ 找不到旧名称(.runner 不存在或解析失败)，临时使用 hostname 作为 runner 名称"
  OLD_NAME="$(hostname)"
else
  echo "   旧名称为: ${OLD_NAME}"
fi

echo "==> 用 ghrunner 删除本地旧配置文件..."
sudo -u "${RUNNER_USER}" bash -lc "
  cd '${RUNNER_DIR}' || exit 0
  rm -f .runner .credentials .credentials_rsaparams .runner.env || true
"

echo "==> 以原名称 [${OLD_NAME}] 重新注册到组织：${ORG_URL} （全程无交互）..."
sudo -u "${RUNNER_USER}" bash -lc "
  cd '${RUNNER_DIR}'
  ./config.sh \
    --url '${ORG_URL}' \
    --token '${RUNNER_TOKEN}' \
    --name '${OLD_NAME}' \
    --runnergroup 'Default' \
    --labels 'self-hosted,linux' \
    --unattended
"

echo "==> root 重新安装并启动服务..."
sudo "${RUNNER_DIR}/svc.sh" install || true
sudo "${RUNNER_DIR}/svc.sh" start

echo
echo \"🎉 迁移完成：Runner 已绑定到 ${ORG_URL}，名称：${OLD_NAME}\"
