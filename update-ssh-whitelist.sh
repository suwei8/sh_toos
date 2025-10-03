#!/bin/bash
set -euo pipefail

# -----------------------
# 配置（按需修改）
# -----------------------
PORT=22
DOMAINS=(
  ssh-mobile-v4.555606.xyz
  wky.555606.xyz
  ssh-vps-v4.555606.xyz
  ssh-vps-v6.555606.xyz
)

# 支持多个局域网网段（IPv4）
LAN_NETS=(
  "10.0.0.0/16"
  # 如果需要可追加更多网段，例如 "192.168.1.0/24"
)

# 链名
CHAIN="SSH_RULES"

# -----------------------
# 前置检查
# -----------------------
command -v iptables >/dev/null 2>&1 || { echo "iptables 未安装或不可用"; exit 1; }
command -v ip6tables >/dev/null 2>&1 || { echo "ip6tables 未安装或不可用"; exit 1; }
command -v dig >/dev/null 2>&1 || echo "warning: dig 未检测到，域名解析将被跳过（建议安装 dnsutils 或 bind9-dnsutils）"

# -----------------------
# helper: 删除可能存在的具体规则（避免重复）
# -----------------------
del_rule_if_exists() {
  local table="$1"     # iptables 或 ip6tables
  shift
  # 尝试删除，忽略错误
  $table -D "$@" 2>/dev/null || true
}

# helper: 添加规则（直接添加，不检查重复——我们在添加前会删除相同规则）
add_rule() {
  local table="$1"; shift
  $table "$@"
}

# -----------------------
# 清理并（重新）创建自定义链（幂等）
# -----------------------
# 解绑 INPUT 指向旧链（若存在）
iptables -D INPUT -p tcp --dport "$PORT" -j "$CHAIN" 2>/dev/null || true
ip6tables -D INPUT -p tcp --dport "$PORT" -j "$CHAIN" 2>/dev/null || true

# 清理旧链（如果存在则 flush & delete），然后新建
if iptables -L "$CHAIN" &>/dev/null; then
  iptables -F "$CHAIN" 2>/dev/null || true
  iptables -X "$CHAIN" 2>/dev/null || true
fi
if ip6tables -L "$CHAIN" &>/dev/null; then
  ip6tables -F "$CHAIN" 2>/dev/null || true
  ip6tables -X "$CHAIN" 2>/dev/null || true
fi

iptables -N "$CHAIN" 2>/dev/null || true
ip6tables -N "$CHAIN" 2>/dev/null || true

# -----------------------
# 在 SSH_RULES 链中添加域名白名单（IPv4/IPv6）
# -----------------------
if command -v dig >/dev/null 2>&1; then
  for d in "${DOMAINS[@]}"; do
    # IPv4
    for ip in $(dig +short A "$d" 2>/dev/null); do
      if [[ -n "$ip" ]]; then
        add_rule iptables -A "$CHAIN" -p tcp -s "$ip" --dport "$PORT" -j ACCEPT
        echo "允许 IPv4 $ip ($d)"
      fi
    done
    # IPv6
    for ip in $(dig +short AAAA "$d" 2>/dev/null); do
      if [[ -n "$ip" ]]; then
        add_rule ip6tables -A "$CHAIN" -p tcp -s "$ip" --dport "$PORT" -j ACCEPT
        echo "允许 IPv6 $ip ($d)"
      fi
    done
  done
else
  echo "跳过域名解析：dig 未安装"
fi

# 默认在链尾 DROP（阻止未在白名单的直连公网 SSH）
add_rule iptables -A "$CHAIN" -j DROP
add_rule ip6tables -A "$CHAIN" -j DROP

# -----------------------
# 在 INPUT 链上按固定顺序插入规则
# 1) lo (IPv4 + IPv6)
# 2) 内网 IPv4 网段（可多个）
# 3) 挂接 SSH_RULES 链（用于公网白名单 + DROP）
# -----------------------

# 先删除可能存在的旧相同规则，保证幂等（不会重复累积）
del_rule_if_exists iptables INPUT -i lo -p tcp --dport "$PORT" -j ACCEPT
del_rule_if_exists ip6tables INPUT -i lo -p tcp --dport "$PORT" -j ACCEPT

for net in "${LAN_NETS[@]}"; do
  del_rule_if_exists iptables INPUT -s "$net" -p tcp --dport "$PORT" -j ACCEPT
done

# 删除旧的跳转（避免多次挂载）
del_rule_if_exists iptables INPUT -p tcp --dport "$PORT" -j "$CHAIN"
del_rule_if_exists ip6tables INPUT -p tcp --dport "$PORT" -j "$CHAIN"

# 插入：1) loopback（保证为第一条规则）
add_rule iptables -I INPUT 1 -i lo -p tcp --dport "$PORT" -j ACCEPT
add_rule ip6tables -I INPUT 1 -i lo -p tcp --dport "$PORT" -j ACCEPT
echo "已允许本地 loopback (127.0.0.1 / ::1) 访问端口 $PORT（位置 1）"

# 插入：2) 内网网段（逐条插入到位置 2、3... 保证优先级高于 SSH_RULES）
pos=2
for net in "${LAN_NETS[@]}"; do
  # 简单判断是否为 IPv4 CIDR（以数字开头）
  if [[ "$net" =~ ^[0-9] ]]; then
    add_rule iptables -I INPUT $pos -s "$net" -p tcp --dport "$PORT" -j ACCEPT
    echo "已允许内网网段 $net 访问端口 $PORT（位置 $pos）"
    pos=$((pos + 1))
  else
    echo "跳过 LAN 网段（格式疑似不为 IPv4）: $net"
  fi
done

# 插入：3) 把 SSH_RULES 链挂到 INPUT（放在后面）
# 使用 -A 避免把它插到最前面，确保 lo 与 LAN 规则在前
add_rule iptables -A INPUT -p tcp --dport "$PORT" -j "$CHAIN"
add_rule ip6tables -A INPUT -p tcp --dport "$PORT" -j "$CHAIN"
echo "已挂接 $CHAIN 到 INPUT（公网连接经过 $CHAIN 判断）"

# -----------------------
# 保存规则（若支持）
# -----------------------
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save || echo "保存到 netfilter-persistent 失败（但规则已生效）"
  echo "✅ 规则已保存到 netfilter-persistent"
elif command -v service >/dev/null 2>&1 && [ -f /etc/init.d/iptables ]; then
  service iptables save || true
  echo "✅ 规则已保存到 /etc/init.d/iptables"
else
  echo "⚠️ 未检测到持久化工具，规则只在当前会话有效（重启后可能丢失）"
fi

# -----------------------
# 状态输出（便于调试）
# -----------------------
echo
echo "📜 最近的 SSH 登录失败记录（如果有）："
if [ -f /var/log/auth.log ]; then
  tail -n 200 /var/log/auth.log | egrep "Failed password|Invalid user|authentication failure|Connection closed by authenticating user" || true
elif [ -f /var/log/secure ]; then
  tail -n 200 /var/log/secure | egrep "Failed password|Invalid user|authentication failure|Connection closed by authenticating user" || true
else
  echo "未找到常见的认证日志文件"
fi

echo
echo "🛡 当前 INPUT 前几条规则（IPv4）："
iptables -L INPUT -n --line-numbers | sed -n '1,12p' || true

echo
echo "🛡 当前 $CHAIN 规则（IPv4）："
iptables -L "$CHAIN" -n --line-numbers || true

echo
echo "🛡 当前 $CHAIN 规则（IPv6）："
ip6tables -L "$CHAIN" -n --line-numbers || true

echo
echo "完成。请确认 cloudflared 服务正在运行并绑定到本地 (127.0.0.1) 或相应端口。"
