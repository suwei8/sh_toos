#!/bin/bash
# 自动更新 Cloudflare IP 并刷新 iptables 规则
# 只允许 Cloudflare 的节点访问 80/443

CF_V4_URL="https://www.cloudflare.com/ips-v4"
CF_V6_URL="https://www.cloudflare.com/ips-v6"
CF_V4_FILE="/etc/cloudflare-ips-v4"
CF_V6_FILE="/etc/cloudflare-ips-v6"

echo "[+] 下载 Cloudflare IP 段..."
curl -s $CF_V4_URL -o $CF_V4_FILE
curl -s $CF_V6_URL -o $CF_V6_FILE

echo "[+] 清理旧规则..."
iptables -F CF_RULES 2>/dev/null
iptables -X CF_RULES 2>/dev/null
ip6tables -F CF_RULES 2>/dev/null
ip6tables -X CF_RULES 2>/dev/null

iptables -N CF_RULES
ip6tables -N CF_RULES

echo "[+] 添加 Cloudflare IPv4 规则..."
while read ip; do
    [ -n "$ip" ] && iptables -A CF_RULES -p tcp -s $ip --dport 80 -j ACCEPT
    [ -n "$ip" ] && iptables -A CF_RULES -p tcp -s $ip --dport 443 -j ACCEPT
done < $CF_V4_FILE

echo "[+] 添加 Cloudflare IPv6 规则..."
while read ip; do
    [ -n "$ip" ] && ip6tables -A CF_RULES -p tcp -s $ip --dport 80 -j ACCEPT
    [ -n "$ip" ] && ip6tables -A CF_RULES -p tcp -s $ip --dport 443 -j ACCEPT
done < $CF_V6_FILE

echo "[+] 添加默认 DROP..."
iptables -A CF_RULES -p tcp --dport 80 -j DROP
iptables -A CF_RULES -p tcp --dport 443 -j DROP
ip6tables -A CF_RULES -p tcp --dport 80 -j DROP
ip6tables -A CF_RULES -p tcp --dport 443 -j DROP

echo "[+] 应用到 INPUT 链..."
iptables -D INPUT -p tcp --dport 80 -j CF_RULES 2>/dev/null
iptables -D INPUT -p tcp --dport 443 -j CF_RULES 2>/dev/null
ip6tables -D INPUT -p tcp --dport 80 -j CF_RULES 2>/dev/null
ip6tables -D INPUT -p tcp --dport 443 -j CF_RULES 2>/dev/null

iptables -I INPUT -p tcp --dport 80 -j CF_RULES
iptables -I INPUT -p tcp --dport 443 -j CF_RULES
ip6tables -I INPUT -p tcp --dport 80 -j CF_RULES
ip6tables -I INPUT -p tcp --dport 443 -j CF_RULES

echo "[+] 安装并保存规则..."
if ! command -v netfilter-persistent &>/dev/null; then
    apt update && apt install -y iptables-persistent
fi

netfilter-persistent save

echo "[+] 完成！Cloudflare 防火墙规则已更新。"
