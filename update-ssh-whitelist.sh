#!/bin/bash
set -euo pipefail

# ===========================================================
# 高安全 SSH 防护脚本（支持多端口 + 域名 + 固定 IP 段白名单）
# 版本：v2.1
# ===========================================================

# -----------------------
# 配置（按需修改）
# -----------------------
# 支持多个监听端口（例如 22, 2053）
PORTS=(
  22
  2053
)

# 域名白名单（自动解析 IPv4/IPv6）
DOMAINS=(
  ssh-mobile-v4.555606.xyz
  wky.555606.xyz
  ssh-vps-v4.555606.xyz
  ssh-vps-v6.555606.xyz
)

# 内网 IPv4 网段
LAN_NETS=(
  "10.0.0.0/16"
  # 可追加更多网段，例如 "192.168.1.0/24"
)

# 固定 IP 段白名单（例如 39.x.x.x）
IP_WHITELIST=(
  "39.0.0.0/8"
  # 可追加更多，如 "123.58.0.0/16"
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
  $table -D "$@" 2>/dev/null || true
}

# helper: 添加规则
add_rule() {
  local table="$1"; shift
  $table "$@"
}

# -----------------------
# 清理旧链并重建
# -----------------------
for p in "${PORTS[@]}"; do
  iptables -D INPUT -p tcp --dport "$p" -j "$CHAIN" 2>/dev/null || true
  ip6tables -D INPUT -p tcp --dport "$p" -j "$CHAIN" 2>/dev/null || true
done

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
# 域名白名单（IPv4 + IPv6）
# -----------------------
if command -v dig >/dev/null 2>&1; then
  for d in "${DOMAINS[@]}"; do
    # IPv4
    for ip in $(dig +short A "$d" 2>/dev/null); do
      if [[ -n "$ip" ]]; then
        for p in "${PORTS[@]}"; do
          add_rule iptables -A "$CHAIN" -p tcp -s "$ip" --dport "$p" -j ACCEPT
        done
        echo "允许 IPv4 $ip ($d) 对端口 ${PORTS[*]}"
      fi
    done
    # IPv6
    for ip in $(dig +short AAAA "$d" 2>/dev/null); do
      if [[ -n "$ip" ]]; then
        for p in "${PORTS[@]}"; do
          add_rule ip6tables -A "$CHAIN" -p tcp -s "$ip" --dport "$p" -j ACCEPT
        done
        echo "允许 IPv6 $ip ($d) 对端口 ${PORTS[*]}"
      fi
    done
  done
else
  echo "跳过域名解析：dig 未安装"
fi

# -----------------------
# 固定 IP 段白名单（例如 39.0.0.0/8）
# -----------------------
for net in "${IP_WHITELIST[@]}"; do
  if [[ "$net" =~ ^[0-9] ]]; then
    for p in "${PORTS[@]}"; do
      add_rule iptables -A "$CHAIN" -p tcp -s "$net" --dport "$p" -j ACCEPT
      echo "允许固定 IPv4 段 $net 访问端口 $p"
    done
  else
    echo "跳过无效 IP 白名单条目: $net"
  fi
done

# -----------------------
# 默认 DROP（非白名单全部丢弃）
# -----------------------
add_rule iptables -A "$CHAIN" -j DROP
add_rule ip6tables -A "$CHAIN" -j DROP

# -----------------------
# INPUT 链处理
# -----------------------
for p in "${PORTS[@]}"; do
  del_rule_if_exists iptables INPUT -i lo -p tcp --dport "$p" -j ACCEPT
  del_rule_if_exists ip6tables INPUT -i lo -p tcp --dport "$p" -j ACCEPT
done

for net in "${LAN_NETS[@]}"; do
  for p in "${PORTS[@]}"; do
    del_rule_if_exists iptables INPUT -s "$net" -p tcp --dport "$p" -j ACCEPT
  done
done

for p in "${PORTS[@]}"; do
  del_rule_if_exists iptables INPUT -p tcp --dport "$p" -j "$CHAIN"
  del_rule_if_exists ip6tables INPUT -p tcp --dport "$p" -j "$CHAIN"
done

# loopback 优先
for p in "${PORTS[@]}"; do
  add_rule iptables -I INPUT 1 -i lo -p tcp --dport "$p" -j ACCEPT
  add_rule ip6tables -I INPUT 1 -i lo -p tcp --dport "$p" -j ACCEPT
  echo "已允许本地 loopback (127.0.0.1 / ::1) 访问端口 $p"
done

# 内网段优先
pos=2
for net in "${LAN_NETS[@]}"; do
  if [[ "$net" =~ ^[0-9] ]]; then
    for p in "${PORTS[@]}"; do
      add_rule iptables -I INPUT $pos -s "$net" -p tcp --dport "$p" -j ACCEPT
      echo "已允许内网网段 $net 访问端口 $p（位置 $pos）"
      pos=$((pos + 1))
    done
  else
    echo "跳过 LAN 网段（格式疑似不为 IPv4）: $net"
  fi
done

# 挂接 SSH_RULES
for p in "${PORTS[@]}"; do
  add_rule iptables -A INPUT -p tcp --dport "$p" -j "$CHAIN"
  add_rule ip6tables -A INPUT -p tcp --dport "$p" -j "$CHAIN"
done
echo "已挂接 $CHAIN 到 INPUT（公网连接经过 $CHAIN 判断） 对端口: ${PORTS[*]}"

# -----------------------
# 持久化保存
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
# 状态输出
# -----------------------
echo
echo "📜 最近的 SSH 登录失败记录："
if [ -f /var/log/auth.log ]; then
  tail -n 200 /var/log/auth.log | egrep "Failed password|Invalid user|authentication failure|Connection closed by authenticating user" || true
elif [ -f /var/log/secure ]; then
  tail -n 200 /var/log/secure | egrep "Failed password|Invalid user|authentication failure|Connection closed by authenticating user" || true
else
  echo "未找到常见的认证日志文件"
fi

echo
echo "🛡 当前 INPUT 规则（IPv4 前30行）："
iptables -L INPUT -n --line-numbers | sed -n '1,30p' || true

echo
echo "🛡 当前 $CHAIN 链规则（IPv4）："
iptables -L "$CHAIN" -n --line-numbers || true

echo
echo "🛡 当前 $CHAIN 链规则（IPv6）："
ip6tables -L "$CHAIN" -n --line-numbers || true

echo
echo "✅ 完成。已对端口 ${PORTS[*]} 应用规则。请确认 cloudflared 服务绑定在本地端口。"
