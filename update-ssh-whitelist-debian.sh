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
command -v nft >/dev/null 2>&1 || { echo "nftables 未安装或不可用"; exit 1; }
command -v dig >/dev/null 2>&1 || echo "warning: dig 未检测到，域名解析将被跳过（建议安装 dnsutils 或 bind9-dnsutils）"

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
# 清理旧链并重建
# -----------------------
for p in "${PORTS[@]}"; do
  nft delete rule ip filter input tcp dport "$p" 2>/dev/null || true
  nft delete rule ip6 filter input tcp dport "$p" 2>/dev/null || true
done

# 删除旧的链
if nft list tables | grep -q "$CHAIN"; then
  nft delete chain ip filter "$CHAIN" 2>/dev/null || true
  nft delete chain ip6 filter "$CHAIN" 2>/dev/null || true
fi

nft add chain ip filter "$CHAIN" { type filter hook input priority 0 \; } 2>/dev/null || true
nft add chain ip6 filter "$CHAIN" { type filter hook input priority 0 \; } 2>/dev/null || true

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
    del_rule_if_exists nft add rule ip filter input_
