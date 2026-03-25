#!/usr/bin/env bash
# ==============================================================================
# 修复脚本：移除导致自动化测试超时的沙盒 Chromium (Snap/Flatpak) 并安装原生核心
# 适用于: Ubuntu 20.04/22.04/24.04 (AMD64 / ARM64)
# 该补丁可平滑修复由于原有错误引导装上的受限浏览器
# ==============================================================================
set -euo pipefail

# 必须使用 root 权限运行
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR]\033[0m 请使用 root 权限运行此修复脚本 (sudo $0)"
    exit 1
fi

echo -e "\033[0;34m========== 开始彻底修复浏览器自动化环境 ==========\033[0m"

# 1. 清理受限制的沙盒版 Chromium 和废弃的自建脚本
echo "[INFO] 正在彻底清理受限的 Snap/Flatpak 版 Chromium 及旧版软链接..."
if command -v snap &>/dev/null; then
    snap remove chromium || true
fi
if command -v flatpak &>/dev/null; then
    flatpak uninstall -y org.chromium.Chromium || true
fi
rm -f /usr/local/bin/chromium-snap /usr/local/bin/chromium-xrdp

# 2. 识别系统架构并安装无沙盒原生版本
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    echo "[INFO] 检测到系统架构为 ARM64，准备使用 Playwright 下载原生 Chromium..."
    
    # 获取默认执行的用户 (优先获取由 sudo 执行时传来的普通用户)
    TARGET_USER=${SUDO_USER:-sw}
    
    if ! id "$TARGET_USER" &>/dev/null; then
        echo -e "\033[0;31m[ERROR]\033[0m 找不到用户 $TARGET_USER，无法切换环境配置 Playwright！"
        exit 1
    fi
    
    echo "[INFO] 正在调用用户 $TARGET_USER 的 Node.js 环境获取 Chromium 核心..."
    sudo -u "$TARGET_USER" bash << EOF
set -e
export HOME="/home/$TARGET_USER"
if [ -s "\$HOME/.nvm/nvm.sh" ]; then
    source "\$HOME/.nvm/nvm.sh"
else
    echo "[WARN] 未自动检测到 nvm 等常规 Node.js 环境，尝试直接调用局部或全局 npm"
fi

mkdir -p "\$HOME/playwright-system-browser"
cd "\$HOME/playwright-system-browser"
npm init -y >/dev/null 2>&1 || true
npm install playwright >/dev/null 2>&1
npx playwright install chromium
EOF

    # 3. 寻找真实 Chromium 路径并配置全局通用软链接
    CHROME_BIN=$(find /home/"$TARGET_USER"/.cache/ms-playwright -name "chrome" -type f | grep "chrome-linux/chrome" | head -n 1 || true)
    if [ -n "$CHROME_BIN" ] && [ -f "$CHROME_BIN" ]; then
        ln -sf "$CHROME_BIN" /usr/local/bin/google-chrome
        ln -sf "$CHROME_BIN" /usr/local/bin/chromium-browser
        ln -sf "$CHROME_BIN" /usr/local/bin/chromium
        echo "[INFO] 修复成功！Chromium (ARM64 Playwright build) 系统软链接已全面配置完成。"
    else
        echo -e "\033[0;31m[ERROR]\033[0m Playwright 下载失败，未找到专属的 Chromium 二进制文件！"
        exit 1
    fi

else
    echo "[INFO] 检测到系统架构为 AMD64/x86_64，准备使用 APT 源安装官方 Google Chrome..."
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor --yes -o /usr/share/keyrings/google-chrome.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y google-chrome-stable
    
    # 创建防呆跨框架适配的软链接，防止自动化工具硬编码了 chromium 的启动程序名
    ln -sf /usr/bin/google-chrome-stable /usr/local/bin/chromium-browser
    ln -sf /usr/bin/google-chrome-stable /usr/local/bin/chromium
    
    echo "[INFO] 修复成功！Google Chrome (AMD64 APT build) 及其别名适配安装完毕。"
fi

echo -e "\033[0;34m========== 修复完成！所有针对网页的自动控制/截图都能无缝触发了 ==========\033[0m"
