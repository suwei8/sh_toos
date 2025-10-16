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
# 自动安装缺少的工具
# -----------------------
# 检查并安装 nftables
if ! command -v nft >/dev/null 2>&1; then
  echo "未检测到 nftables，正在安装 nftables..."
  apt update && apt install nftables -y
fi

# 检查并安装 dig（域名解析工具）
if ! command -v dig >/dev/null 2>&1; then
  echo "未检测到 dig，正在安装 dnsutils..."
  apt update && apt install dnsutils -y
fi

# -----------------------
# helper: 删除可能存在的具体规则（避免重复）
# -----------------------
del_rule_if_exists() {
  local table="$1"     # nftables
  shift
  $table delete "$@" 2>/dev/null || true
}

# helper: 添加规则
add_rule() {
  local table="$1"; shift
  $table "$@"
}

# -----------------------
# 确保链存在
# -----------------------
if ! nft list chains ip filter | grep -q "$CHAIN"; then
  nft add chain ip filter "$CHAIN" { type filter hook input priority 0 \; }
  nft add chain ip6 filter "$CHAIN" { type filter hook input priority 0 \; }
  echo "已创建链 $CHAIN"
fi

# -----------------------
# 清理旧链并重建
# -----------------------
for p in "${PORTS[@]}"; do
  nft delete rule ip filter input tcp dport "$p" 2>/dev/null || true
  nft delete rule ip6 filter input tcp dport "$p" 2>/dev/null || true
done

# -----------------------
# 域名白名单（IPv4 + IPv6）
# -----------------------
if command -v dig >/dev/null 2>&1; then
  for d in "${DOMAINS[@]}"; do
    # IPv4
    for ip in $(dig +short A "$d" 2>/dev/null); do
      if [[ -n "$ip" ]]; then
        for p in "${PORTS[@]}"; do
          add_rule nft add rule ip filter "$CHAIN" ip saddr "$ip" tcp dport "$p" accept
        done
        echo "允许 IPv4 $ip ($d) 对端口 ${PORTS[*]}"
      fi
    done
    # IPv6
    for ip in $(dig +short AAAA "$d" 2>/dev/null); do
      if [[ -n "$ip" ]]; then
        for p in "${PORTS[@]}"; do
          add_rule nft add rule ip6 filter "$CHAIN" ip6 saddr "$ip" tcp dport "$p" accept
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
      add_rule nft add rule ip filter "$CHAIN" ip saddr "$net" tcp dport "$p" accept
      echo "允许固定 IPv4 段 $net 访问端口 $p"
    done
  else
    echo "跳过无效 IP 白名单条目: $net"
  fi
done

# -----------------------
# 默认 DROP（非白名单全部丢弃）
# -----------------------
add_rule nft add rule ip filter "$CHAIN" drop
add_rule nft add rule ip6 filter "$CHAIN" drop

# -----------------------
# INPUT 链处理
# -----------------------
for p in "${PORTS[@]}"; do
  del_rule_if_exists nft add rule ip filter input iifname lo tcp dport "$p" accept
  del_rule_if_exists nft add rule ip6 filter input iifname lo tcp dport "$p" accept
done

for net in "${LAN_NETS[@]}"; do
  for p in "${PORTS[@]}"; do
    del_rule_if_exists nft add rule ip filter input ip saddr "$net" tcp dport "$p" accept
  done
done

for p in "${PORTS[@]}"; do
  del_rule_if_exists nft add rule ip filter input tcp dport "$p" jump "$CHAIN"
  del_rule_if_exists nft add rule ip6 filter input tcp dport "$p" jump "$CHAIN"
done

# loopback 优先
for p in "${PORTS[@]}"; do
  add_rule nft add rule ip filter input iifname lo tcp dport "$p" accept
  add_rule nft add rule ip6 filter input iifname lo tcp dport "$p" accept
  echo "已允许本地 loopback (127.0.0.1 / ::1) 访问端口 $p"
done

# 内网段优先
pos=2
for net in "${LAN_NETS[@]}"; do
  if [[ "$net" =~ ^[0-9] ]]; then
    for p in "${PORTS[@]}"; do
      add_rule nft add rule ip filter input ip saddr "$net" tcp dport "$p" accept
      echo "已允许内网网段 $net 访问端口 $p（位置 $pos）"
      pos=$((pos + 1))
    done
  else
    echo "跳过 LAN 网段（格式疑似不为 IPv4）: $net"
  fi
done

# 挂接 SSH_RULES
for p in "${PORTS[@]}"; do
  add_rule nft add rule ip filter input tcp dport "$p" jump "$CHAIN"
  add_rule nft add rule ip6 filter input tcp dport "$p" jump "$CHAIN"
done
echo "已挂接 $CHAIN 到 INPUT（公网连接经过 $CHAIN 判断） 对端口: ${PORTS[*]}"

# -----------------------
# 持久化保存
# -----------------------
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save || echo "保存到 netfilter-persistent 失败（但规则已生效）"
  echo "✅ 规则已保存到 netfilter-persistent"
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
nft list ruleset | head -n 30 || true

echo
echo "🛡 当前 $CHAIN 链规则（IPv4）："
nft list ruleset | grep "$CHAIN" || true

echo
echo "🛡 当前 $CHAIN 链规则（IPv6）："
nft list ruleset | grep "$CHAIN" || true

echo
echo "✅ 完成。已对端口 ${PORTS[*]} 应用规则。请确认 cloudflared 服务绑定在本地端口。"
