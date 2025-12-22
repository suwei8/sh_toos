#!/bin/bash
# 自动创建用户 sw，配置免密 sudo 和 docker 组

set -e

USERNAME="sw"
PASSWORD="sw63828"

echo "[+] 创建用户 $USERNAME..."
if id "$USERNAME" &>/dev/null; then
    echo "[*] 用户 $USERNAME 已存在，跳过创建"
else
    useradd -m -s /bin/bash "$USERNAME"
    echo "[+] 用户 $USERNAME 创建成功"
fi

echo "[+] 设置用户密码..."
echo "$USERNAME:$PASSWORD" | chpasswd
echo "[+] 密码设置成功"

echo "[+] 配置免密 sudo..."
SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
echo "[+] 免密 sudo 配置成功"

echo "[+] 添加到 docker 组..."
if getent group docker &>/dev/null; then
    usermod -aG docker "$USERNAME"
    echo "[+] 已添加到 docker 组"
else
    echo "[!] docker 组不存在，请先安装 Docker"
    echo "[*] 安装 Docker 后可手动执行: usermod -aG docker $USERNAME"
fi

echo ""
echo "=========================================="
echo "[+] 完成！用户配置如下："
echo "    用户名: $USERNAME"
echo "    密码: $PASSWORD"
echo "    Sudo: 免密"
echo "    Docker: $(groups $USERNAME 2>/dev/null | grep -q docker && echo '已配置' || echo '待配置')"
echo "=========================================="
echo ""
echo "[*] 切换用户: su - $USERNAME"
