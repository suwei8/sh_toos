#!/usr/bin/env bash
# ==============================================================================
# 全自动远程开发环境部署脚本
# 适用于: Oracle Cloud VM.Standard.A1.Flex (ARM64) + Ubuntu 20.04.6 LTS
# ==============================================================================
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
NEW_USER="sw"
NEW_PASSWORD="sw63828"
GIT_USER_NAME="suwei8"
GIT_USER_EMAIL="suwei8@outlook.com"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}========== $1 ==========${NC}"; }

# ==============================================================================
# 1. 创建用户并配置免密 sudo
# ==============================================================================
setup_user() {
    log_section "1. 创建用户 ${NEW_USER} 并配置免密 sudo"
    
    if id "${NEW_USER}" &>/dev/null; then
        log_warn "用户 ${NEW_USER} 已存在，跳过创建"
    else
        log_info "创建用户 ${NEW_USER}..."
        useradd -m -s /bin/bash "${NEW_USER}"
        echo "${NEW_USER}:${NEW_PASSWORD}" | chpasswd
        log_info "用户 ${NEW_USER} 创建成功，密码已设置"
    fi
    
    # 配置免密 sudo
    log_info "配置免密 sudo..."
    echo "${NEW_USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${NEW_USER}-nopasswd"
    chmod 440 "/etc/sudoers.d/${NEW_USER}-nopasswd"
    
    # 添加到 docker 组（如果存在）
    if getent group docker &>/dev/null; then
        usermod -aG docker "${NEW_USER}"
        log_info "用户已添加到 docker 组"
    fi
    
    log_info "用户配置完成"
}

# ==============================================================================
# 2. 安装中文语言包
# ==============================================================================
install_chinese_language() {
    log_section "2. 安装中文语言包"
    
    apt-get update -qq
    apt-get install -y language-pack-zh-hans fonts-noto-cjk fonts-noto-cjk-extra
    
    # 更新 locale
    locale-gen zh_CN.UTF-8
    update-locale LANG=en_US.UTF-8
    
    log_info "中文语言包安装完成"
}

# ==============================================================================
# 3. 安装 XFCE + LightDM 桌面环境
# ==============================================================================
install_desktop() {
    log_section "3. 安装 XFCE + LightDM 桌面环境"
    
    apt-get update -qq
    
    # 预配置 lightdm 为默认显示管理器（避免交互式询问）
    log_info "预配置 lightdm 为默认显示管理器..."
    echo "lightdm shared/default-x-display-manager select lightdm" | debconf-set-selections
    
    # 使用非交互模式安装
    DEBIAN_FRONTEND=noninteractive apt-get install -y xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
    
    # 配置 LightDM 为默认显示管理器
    echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager
    
    # 为用户配置默认 XFCE 会话
    USER_HOME="/home/${NEW_USER}"
    mkdir -p "${USER_HOME}/.config"
    echo "[Desktop]
Session=xfce
" > "${USER_HOME}/.dmrc"
    chown -R "${NEW_USER}:${NEW_USER}" "${USER_HOME}/.config" "${USER_HOME}/.dmrc"
    
    log_info "XFCE + LightDM 桌面环境安装完成"
}

# ==============================================================================
# 4. 安装并配置 xRDP
# ==============================================================================
install_xrdp() {
    log_section "4. 安装并配置 xRDP"
    
    apt-get install -y xrdp xorgxrdp
    
    # 将 xrdp 用户添加到 ssl-cert 组
    usermod -aG ssl-cert xrdp
    
    # 注意: 保持默认端口配置 (port=3389)
    # xRDP 默认监听 0.0.0.0:3389，通过 Cloudflare Tunnel 访问时安全
    # 如需仅监听本地，可手动修改为 port=tcp://.:3389
    
    # 关键修复: 修改 startwm.sh 以启动 XFCE 并支持 Chromium snap
    log_info "配置 startwm.sh 启动 XFCE 桌面..."
    cat > /etc/xrdp/startwm.sh << 'STARTWM_EOF'
#!/bin/sh
if test -r /etc/profile; then . /etc/profile; fi
if test -r /etc/default/locale; then . /etc/default/locale; fi

# --- FIX FOR CHROMIUM/SNAPS NOT OPENING ---
# 1. Unset variables that confuse the Snap sandbox
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
# 2. Grant permission to the X server (fixes "No protocol specified")
xhost +si:localuser:$(whoami)
# ------------------------------------------

startxfce4
STARTWM_EOF
    chmod +x /etc/xrdp/startwm.sh
    
    # 禁用 polkit 颜色管理设备认证弹窗
    # "Authentication is required to create a color managed device"
    log_info "禁用颜色管理设备认证弹窗..."
    cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla << 'POLKIT_EOF'
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
POLKIT_EOF
    
    # 启用并启动 xRDP 服务
    systemctl enable xrdp
    systemctl restart xrdp
    
    log_info "xRDP 安装并配置完成"
}

# ==============================================================================
# 5. 安装 Chromium 浏览器 (via snap)
# ==============================================================================
install_chromium() {
    log_section "5. 安装 Chromium 浏览器 (via snap)"
    
    # 确保 snapd 已安装并运行
    if ! command -v snap &>/dev/null; then
        apt-get install -y snapd
        systemctl enable snapd
        systemctl start snapd
        sleep 5  # 等待 snapd 初始化
    fi
    
    # 安装 Chromium snap
    if snap list chromium &>/dev/null; then
        log_warn "Chromium snap 已安装"
        snap refresh chromium
    else
        snap install chromium
    fi
    
    log_info "Chromium 浏览器安装完成"
    log_info "版本: $(snap list chromium | tail -1 | awk '{print $2}')"
}

# ==============================================================================
# 6. 安装 Docker + Compose
# ==============================================================================
install_docker() {
    log_section "6. 安装 Docker + Compose"
    
    # 移除旧版本（忽略错误）
    apt-get remove -y docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc 2>/dev/null || true
    
    # 安装依赖
    apt-get update -qq
    apt-get install -y ca-certificates curl
    
    # 添加 Docker GPG 密钥
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    
    # 添加仓库
    tee /etc/apt/sources.list.d/docker.sources << 'DOCKER_EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: focal
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
DOCKER_EOF
    
    # 安装 Docker
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # 将用户添加到 docker 组
    usermod -aG docker "${NEW_USER}"
    
    # 启用并启动 Docker
    systemctl enable docker
    systemctl start docker
    
    log_info "Docker 安装完成"
    docker --version
    docker compose version
}

# ==============================================================================
# 7. 安装 Node.js (via nvm) - 为指定用户安装
# ==============================================================================
install_nodejs() {
    log_section "7. 安装 Node.js (via nvm)"
    
    USER_HOME="/home/${NEW_USER}"
    
    # 以指定用户身份安装 nvm 和 Node.js
    sudo -u "${NEW_USER}" bash << 'NVM_EOF'
set -e

# 安装 nvm
export HOME="/home/sw"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# 加载 nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# 安装 Node.js 24
nvm install 24

# 验证
echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"
NVM_EOF
    
    log_info "Node.js 安装完成"
}

# ==============================================================================
# 8. 安装 gemini-cli
# ==============================================================================
install_gemini_cli() {
    log_section "8. 安装 gemini-cli"
    
    # 以指定用户身份安装
    sudo -u "${NEW_USER}" bash << 'GEMINI_EOF'
set -e
export HOME="/home/sw"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

npm install -g @google/gemini-cli

# 自动确认安装扩展（使用 yes 命令自动回答 Y）
yes | gemini extensions install https://github.com/ChromeDevTools/chrome-devtools-mcp || true
GEMINI_EOF
    
    log_info "gemini-cli 安装完成"
}

# ==============================================================================
# 9. 安装 Google Antigravity
# ==============================================================================
install_antigravity() {
    log_section "9. 安装 Google Antigravity"
    
    # 添加仓库密钥
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
        gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
    
    # 添加仓库
    echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
        tee /etc/apt/sources.list.d/antigravity.list > /dev/null
    
    # 安装
    apt-get update -qq
    apt-get install -y antigravity
    
    log_info "Google Antigravity 安装完成"
    antigravity --version || true
}

# ==============================================================================
# 10. 安装 cloudflared
# ==============================================================================
install_cloudflared() {
    log_section "10. 安装 cloudflared"
    
    # 添加 Cloudflare GPG 密钥
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | \
        tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
    
    # 添加仓库
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | \
        tee /etc/apt/sources.list.d/cloudflared.list
    
    # 安装
    apt-get update -qq
    apt-get install -y cloudflared
    
    log_info "cloudflared 安装完成"
    cloudflared --version
}

# ==============================================================================
# 11. 配置 Git 和生成 SSH 密钥
# ==============================================================================
setup_git() {
    log_section "11. 配置 Git 和生成 SSH 密钥"
    
    USER_HOME="/home/${NEW_USER}"
    
    # 以指定用户身份配置
    sudo -u "${NEW_USER}" bash << GIT_EOF
set -e
export HOME="${USER_HOME}"

# Git 配置
git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"

# 生成 SSH 密钥（如果不存在）
if [[ ! -f "\${HOME}/.ssh/id_ed25519" ]]; then
    ssh-keygen -t ed25519 -C "${GIT_USER_EMAIL}" -f "\${HOME}/.ssh/id_ed25519" -N ""
    echo ""
    echo "=========================================="
    echo "SSH 公钥（请添加到 GitHub）:"
    echo "=========================================="
    cat "\${HOME}/.ssh/id_ed25519.pub"
    echo "=========================================="
else
    echo "SSH 密钥已存在"
    cat "\${HOME}/.ssh/id_ed25519.pub"
fi
GIT_EOF
    
    log_info "Git 配置完成"
}

# ==============================================================================
# Main Execution
# ==============================================================================
main() {
    # 检查是否以 root 运行
    if [[ $EUID -ne 0 ]]; then
        log_err "请使用 root 权限运行此脚本 (sudo $0)"
        exit 1
    fi
    
    # 检查架构
    ARCH=$(uname -m)
    if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
        log_warn "当前架构为 $ARCH，此脚本针对 ARM64 优化"
    fi
    
    # 检查 Ubuntu 版本
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "${VERSION_ID:-}" != "20.04" ]]; then
            log_warn "当前 Ubuntu 版本为 ${VERSION_ID:-unknown}，此脚本针对 20.04 优化"
        fi
    fi
    
    log_info "开始执行全自动远程开发环境部署..."
    log_info "目标用户: ${NEW_USER}"
    
    setup_user
    install_chinese_language
    install_desktop
    install_xrdp
    install_chromium
    install_docker
    install_nodejs
    install_gemini_cli
    install_antigravity
    install_cloudflared
    setup_git
    
    log_section "部署完成!"
    echo ""
    log_info "部署摘要:"
    echo "  - 用户: ${NEW_USER} (密码: ${NEW_PASSWORD})"
    echo "  - 桌面: XFCE + LightDM"
    echo "  - xRDP: 127.0.0.1:3389 (使用 Cloudflare Tunnel 访问)"
    echo "  - Chromium: via snap (已配置 xRDP 兼容修复)"
    echo "  - Docker: 已安装"
    echo "  - Node.js: via nvm (v24)"
    echo "  - gemini-cli: 已安装"
    echo "  - Antigravity: 已安装"
    echo "  - cloudflared: 已安装"
    echo ""
    log_warn "建议重启系统以确保所有配置生效: sudo reboot"
}

main "$@"
