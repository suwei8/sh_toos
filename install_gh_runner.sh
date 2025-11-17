#!/usr/bin/env bash
set -euo pipefail

#########################
# 可配置项（每台机器前先改）
#########################

# 你的 GitHub 仓库地址
REPO_URL="https://github.com/suwei8/oci-ops"

# Runner 版本与校验值（和你原来命令一致）
RUNNER_VERSION="2.329.0"
RUNNER_SHA256="194f1e1e4bd02f80b7e9633fc546084d8d4e19f3928a324d512ea53430102e1d"

# 创建的系统用户
RUNNER_USER="ghrunner"
# 给 ghrunner 设置的系统登录密码（如不需要登录，可以随便设一个复杂密码即可）
RUNNER_PASSWORD="sw63828"

#########################
# 运行时输入 runner token
#########################

if [[ $EUID -ne 0 ]]; then
  echo "请用 root 用户或通过 sudo 执行此脚本."
  exit 1
fi

read -rp "请输入 GitHub Runner 注册用的 TOKEN: " RUNNER_TOKEN
if [[ -z "${RUNNER_TOKEN}" ]]; then
  echo "TOKEN 不能为空."
  exit 1
fi

RUNNER_HOME="/home/${RUNNER_USER}"
RUNNER_DIR="${RUNNER_HOME}/actions-runner"

echo "==> 检查/创建用户 ${RUNNER_USER} ..."
if ! id "${RUNNER_USER}" &>/dev/null; then
  useradd -m -s /bin/bash "${RUNNER_USER}"
  echo "${RUNNER_USER}:${RUNNER_PASSWORD}" | chpasswd
  usermod -aG sudo "${RUNNER_USER}"
  echo "用户 ${RUNNER_USER} 已创建并加入 sudo 组."
else
  echo "用户 ${RUNNER_USER} 已存在，跳过创建."
fi

echo "==> 以 ${RUNNER_USER} 用户下载并解压 GitHub Actions Runner ..."
sudo -u "${RUNNER_USER}" bash -lc "
set -euo pipefail
mkdir -p '${RUNNER_DIR}'
cd '${RUNNER_DIR}'

FILE=\"actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz\"

if [[ ! -f \"\$FILE\" ]]; then
  echo '下载 runner 压缩包 ...'
  curl -o \"\$FILE\" -L \"https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/\$FILE\"
else
  echo '已存在压缩包 \$FILE，跳过下载.'
fi

echo '校验压缩包 SHA256 ...'
echo '${RUNNER_SHA256}  '\$FILE | shasum -a 256 -c

echo '解压 runner ...'
tar xzf \"./\$FILE\"

echo '即将执行 ./config.sh，请根据提示完成交互（runner 名称等）...'
./config.sh --url '${REPO_URL}' --token '${RUNNER_TOKEN}'
"

echo "==> 安装并启动 runner 服务 ..."
cd "${RUNNER_DIR}"
./svc.sh install
./svc.sh start

echo "==> GitHub Actions Runner 已安装并以服务方式启动."
echo "仓库：${REPO_URL}"
echo "用户：${RUNNER_USER}"
