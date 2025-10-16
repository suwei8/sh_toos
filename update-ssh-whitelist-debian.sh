#!/bin/bash
set -euo pipefail

# -----------------------
# 配置（按需修改）
# -----------------------
PORTS=(22 2053)

DOMAINS=(
  ssh-mobile-v4.555606.xyz
  wky.555606.xyz
  ssh-vps-v4.555606.xyz
  ssh-vps-v6.555606.xyz
)

LAN_NETS=(
  "10.0.0.0/16"
)

IP_WHITELIST=(
  "39.0.0.0/8"
)

CHAIN="SSH_RULES"

# -----------------------
# 自动安装缺少的工具
# -----------------------
# 检查并安装 iptables
if ! command -v iptables >/dev/null 2>&1; then
  echo "未检测到 iptables，正在安装 iptables..."
  apt update && apt install iptables -y
fi

# -----------------------
# 创建 SSH_RULES 链
# -----------------------
# 确保 filter 表和 SSH_RULES 链存在
iptables -t filter -N SSH_RULES || true

# -----------------------
# 清理旧链并重建
# -----------------------
for p in "${PORTS[@]}"; do
  iptables -t filter -D INPUT -p tcp --dport "$p" -j SSH_RULES || true
done

# -----------------------
# 域名白名单（IPv4 + IPv6）
# -----------------------
if command -v dig >/dev/null 2>&1; then
  for d in "${DOMAINS[@]}"; do
    for ip in $(dig +short A "$d" 2>/dev/null); do
      if [[ -n "$ip" ]]; then
        for p in "${PORTS[@]}"; do
          iptables -t filter -A SSH_RULES -s "$ip" -p tcp --dport "$p" -j ACCEPT
          echo "允许 IPv4 $ip ($d) 对端口 ${PORTS[*]}"
        done
      fi
    done
    for ip in $(dig +short AAAA "$d" 2>/dev/null); do
      if [[ -n "$ip" ]]; then
        for p in "${PORTS[@]}"; do
          ip6tables -t filter -A SSH_RULES -s "$ip" -p tcp --dport "$p" -j ACCEPT
          echo "允许 IPv6 $ip ($d) 对端口 ${PORTS[*]}"
        done
      fi
    done
  done
else
  echo "跳过域名解析：dig 未安装"
fi

# -----------------------
# 固定 IP 段白名单
# -----------------------
for net in "${IP_WHITELIST[@]}"; do
  for p in "${PORTS[@]}"; do
    iptables -t filter -A SSH_RULES -s "$net" -p tcp --dport "$p" -j ACCEPT
    echo "允许固定 IPv4 段 $net 访问端口 $p"
  done
done

# -----------------------
# 默认 DROP（非白名单全部丢弃）
# -----------------------
iptables -t filter -A SSH_RULES -j DROP

# -----------------------
# 添加规则到 INPUT 链
# -----------------------
for p in "${PORTS[@]}"; do
  iptables -t filter -A INPUT -p tcp --dport "$p" -j SSH_RULES
done

# -----------------------
# 允许本地接口的访问
# -----------------------
for p in "${PORTS[@]}"; do
  iptables -t filter -A INPUT -i lo -p tcp --dport "$p" -j ACCEPT
  echo "已允许本地 loopback (127.0.0.1) 访问端口 $p"
done

# -----------------------
# 持久化保存
# -----------------------
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save || echo "保存到 netfilter-persistent 失败（但规则已生效）"
  echo "规则已保存到 netfilter-persistent"
else
  echo "未检测到持久化工具，规则只在当前会话有效（重启后可能丢失）"
fi

# 输出当前规则
echo "当前的 SSH_RULES 链规则（IPv4）："
iptables -t filter -L SSH_RULES
