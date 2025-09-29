#!/bin/bash
PORT=22
DOMAINS=(
  ssh-mobile-v4.555606.xyz
  wky.555606.xyz
  ssh-vps-v4.555606.xyz
  ssh-vps-v6.555606.xyz
)

# 清理旧规则链
iptables -F SSH_RULES 2>/dev/null
ip6tables -F SSH_RULES 2>/dev/null
iptables -X SSH_RULES 2>/dev/null
ip6tables -X SSH_RULES 2>/dev/null

iptables -N SSH_RULES
ip6tables -N SSH_RULES

for d in "${DOMAINS[@]}"; do
  # IPv4
  for ip in $(dig +short A $d); do
    iptables -A SSH_RULES -p tcp -s $ip --dport $PORT -j ACCEPT
    echo "允许 IPv4 $ip ($d)"
  done
  # IPv6
  for ip in $(dig +short AAAA $d); do
    ip6tables -A SSH_RULES -p tcp -s $ip --dport $PORT -j ACCEPT
    echo "允许 IPv6 $ip ($d)"
  done
done

# 默认 DROP
iptables -A SSH_RULES -j DROP
ip6tables -A SSH_RULES -j DROP

# 应用到 INPUT 链
iptables -D INPUT -p tcp --dport $PORT -j SSH_RULES 2>/dev/null
ip6tables -D INPUT -p tcp --dport $PORT -j SSH_RULES 2>/dev/null
iptables -I INPUT -p tcp --dport $PORT -j SSH_RULES
ip6tables -I INPUT -p tcp --dport $PORT -j SSH_RULES

# 检查并安装 iptables-persistent（Debian/Ubuntu）
if ! command -v netfilter-persistent >/dev/null 2>&1; then
  if [ -f /etc/debian_version ]; then
    echo "未检测到 iptables-persistent，正在安装..."
    apt update && apt install -y iptables-persistent
  fi
fi

# 保存规则
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
  echo "✅ 规则已保存到 netfilter-persistent"
elif command -v service >/dev/null 2>&1 && [ -f /etc/init.d/iptables ]; then
  service iptables save
  echo "✅ 规则已保存到 /etc/init.d/iptables"
else
  echo "⚠️ 未检测到规则保存工具，规则只在当前会话生效（重启后会丢失）"
fi

# =============================
# 🔹 附加功能：日志检查 + 状态查看
# =============================

echo ""
echo "📜 最近的 SSH 登录失败记录："
if [ -f /var/log/auth.log ]; then
  tail -n 200 /var/log/auth.log | egrep "Failed password|Invalid user|authentication failure|Connection closed by authenticating user"
elif [ -f /var/log/secure ]; then   # CentOS 使用 /var/log/secure
  tail -n 200 /var/log/secure | egrep "Failed password|Invalid user|authentication failure|Connection closed by authenticating user"
fi

echo ""
echo "🛡 当前 IPv4 SSH_RULES："
iptables -L SSH_RULES -n

echo ""
echo "🛡 当前 IPv6 SSH_RULES："
ip6tables -L SSH_RULES -n

echo ""
echo "🧹 清理认证日志..."
if [ -f /var/log/auth.log ]; then
  truncate -s 0 /var/log/auth.log
  echo "✅ 已清空 /var/log/auth.log"
elif [ -f /var/log/secure ]; then
  truncate -s 0 /var/log/secure
  echo "✅ 已清空 /var/log/secure"
fi
