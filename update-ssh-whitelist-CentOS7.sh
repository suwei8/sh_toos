#!/bin/bash
PORT=22
DOMAINS=(
  ssh-mobile-v4.555606.xyz
  wky.555606.xyz
  ssh-vps-v4.555606.xyz
  ssh-vps-v6.555606.xyz
)

# 确保 dig 命令存在
if ! command -v dig >/dev/null 2>&1; then
  echo "未检测到 dig，正在安装 bind-utils..."
  yum install -y bind-utils
fi

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

# 确保 iptables-services 存在
if ! rpm -q iptables-services >/dev/null 2>&1; then
  echo "未检测到 iptables-services，正在安装..."
  yum install -y iptables-services
  systemctl enable iptables
  systemctl enable ip6tables
fi

# 保存规则
if systemctl is-active --quiet iptables; then
  service iptables save
  echo "✅ IPv4 规则已保存 (/etc/sysconfig/iptables)"
fi

if systemctl is-active --quiet ip6tables; then
  service ip6tables save
  echo "✅ IPv6 规则已保存 (/etc/sysconfig/ip6tables)"
fi

echo "🎉 配置完成！规则已生效。"
