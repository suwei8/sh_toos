#!/bin/bash
set -u

# 修复脚本：解决 xfce4-terminal 中文乱码问题

USER_NAME="sw"
USER_HOME="/home/${USER_NAME}"

if [[ "$(whoami)" != "root" ]]; then
    echo "请使用 sudo 运行此脚本: sudo $0"
    exit 1
fi

echo "1. 重新生成 Locales..."
locale-gen en_US.UTF-8 zh_CN.UTF-8

echo "2. 更新系统 Locale 配置..."
update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 LANGUAGE=zh_CN:en_US

echo "3. 更新 xfce4-terminal 配置 (强制 UTF-8)..."
mkdir -p "${USER_HOME}/.config/xfce4/terminal"

CONFIG_FILE="${USER_HOME}/.config/xfce4/terminal/terminalrc"

# 如果文件存在，确保 Encoding 被设置为 UTF-8
if [[ -f "$CONFIG_FILE" ]]; then
    if grep -q "Encoding=" "$CONFIG_FILE"; then
        sed -i 's/Encoding=.*/Encoding=UTF-8/' "$CONFIG_FILE"
    else
        sed -i '/\[Configuration\]/a Encoding=UTF-8' "$CONFIG_FILE"
    fi
else
    # 如果文件不存在，创建新文件
    cat > "$CONFIG_FILE" << 'EOF'
[Configuration]
Encoding=UTF-8
EOF
fi

# 确保权限正确
chown -R "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.config"

echo "4. 更新 Shell 环境变量..."
LOCALE_CONF="
# Force Locale to UTF-8
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
export LANGUAGE=zh_CN:en_US
"
if ! grep -q "LC_ALL=zh_CN.UTF-8" "${USER_HOME}/.profile"; then
    echo "$LOCALE_CONF" >> "${USER_HOME}/.profile"
fi
if ! grep -q "LC_ALL=zh_CN.UTF-8" "${USER_HOME}/.bashrc"; then
    echo "$LOCALE_CONF" >> "${USER_HOME}/.bashrc"
fi
chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.profile" "${USER_HOME}/.bashrc"

echo "修复完成！"
echo "请关闭所有打开的终端窗口并重新打开，或注销并重新登录。"
