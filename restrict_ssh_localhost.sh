#!/bin/bash
# 限制 SSH 服务只监听本地端口（127.0.0.1）
# 阻止外部直接访问，只允许 Cloudflare Tunnel 连接

set -e

SSHD_CONFIG="/etc/ssh/sshd_config"

echo "[+] 检查 SSH 配置文件..."
if [ ! -f "$SSHD_CONFIG" ]; then
    echo "[-] 错误: SSH 配置文件 $SSHD_CONFIG 不存在"
    exit 1
fi

echo "[+] 检查当前 ListenAddress 配置..."
if grep -q "^ListenAddress 127.0.0.1" "$SSHD_CONFIG"; then
    echo "[*] ListenAddress 127.0.0.1 已存在，无需修改"
else
    echo "[+] 添加 ListenAddress 127.0.0.1 配置..."
    
    # 尝试在 #ListenAddress 0.0.0.0 下方添加
    if grep -q "^#ListenAddress 0.0.0.0" "$SSHD_CONFIG"; then
        sudo sed -i '/^#ListenAddress 0.0.0.0/a ListenAddress 127.0.0.1' "$SSHD_CONFIG"
        echo "[+] 已在 #ListenAddress 0.0.0.0 下方添加"
    # 如果没有找到注释行，尝试在其他 ListenAddress 配置附近添加
    elif grep -q "^#ListenAddress" "$SSHD_CONFIG"; then
        sudo sed -i '0,/^#ListenAddress/a ListenAddress 127.0.0.1' "$SSHD_CONFIG"
        echo "[+] 已在 #ListenAddress 下方添加"
    # 如果都没有，在文件末尾添加
    else
        echo "ListenAddress 127.0.0.1" | sudo tee -a "$SSHD_CONFIG" > /dev/null
        echo "[+] 已在配置文件末尾添加"
    fi
fi

echo "[+] 重启 SSH 服务..."
# 兼容不同系统的 SSH 服务名称 (ssh 或 sshd)
if systemctl list-units --type=service --all | grep -q "ssh.service"; then
    sudo systemctl restart ssh
    echo "[+] 已重启 ssh.service"
elif systemctl list-units --type=service --all | grep -q "sshd.service"; then
    sudo systemctl restart sshd
    echo "[+] 已重启 sshd.service"
else
    echo "[-] 错误: 找不到 SSH 服务"
    exit 1
fi

echo "[+] 验证监听端口..."
echo "----------------------------------------"
sudo ss -tlnp | grep ssh
echo "----------------------------------------"

echo ""
echo "[+] 获取公网 IP 地址..."
PUBLIC_IP=$(curl -4 -s ifconfig.me)
echo "----------------------------------------"
echo "公网 IP: $PUBLIC_IP"
echo "----------------------------------------"

echo ""
echo "[+] 完成！SSH 服务现在只监听 127.0.0.1"
echo "[!] 警告: 外部 SSH 连接已被阻止，请确保 Cloudflare Tunnel 已正确配置"
echo ""
echo "[*] 验证方法: 从其他网络尝试连接 ssh root@$PUBLIC_IP 应该超时或拒绝连接"
