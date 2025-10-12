#!/bin/bash
set -euo pipefail

# ===========================================================
# 高安全 SSH 防护脚本（支持多端口 + 域名 + 固定 IP 段白名单）
# 兼容 CentOS 7（持久化使用 iptables-save 或 iptables-services）
# 版本：v2.1-centos7
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
command -v iptables >/dev/null 2>&1 || { echo "iptables 未安装或不可用，请安装 iptables（或 iptables-services）"; exit 1; }
# ip6tables 不是必需的，但如果不存在，IPv6 部分会跳过
IP6TABLES_AVAILABLE=true
if ! command -v ip6tables >/dev/null 2>&1; then
  IP6TABLES_AVAILABLE=false
  echo "提示：未检测到 ip6tables，IPv6 相关规则将被跳过（如果需要 IPv6，请安装 ip6tables）"
fi

if command -v dig >/dev/null 2>&1; then
  :
else
  echo "warning: dig 未检测到，域名解析将被跳过（在 CentOS 上请安装 bind-utils：yum install -y bind-utils）"
fi

# -----------------------
# helper: 删除可能存在的具体规则（避免重复）
# $1 = 命令（iptables 或 ip6tables），后面为整条规则参数
# -----------------------
del_rule_if_exists() {
  local table_cmd="$1"
  shift
  # 用 -D 删除指定规则行（如果不存在，忽略错误）
  "$table_cmd" -D "$@" 2>/dev/null || true
}

# helper: 添加规则（包装，便于统一日志调整）
add_rule() {
  local table_cmd="$1"; shift
  "$table_cmd" "$@"
}

# -----------------------
# 清理旧链并重建
# -----------------------
for p in "${PORTS[@]}"; do
  iptables -D INPUT -p tcp --dport "$p" -j "$CHAIN" 2>/dev/null || true
  if $IP6TABLES_AVAILABLE; then
    ip6tables -D INPUT -p tcp --dport "$p" -j "$CHAIN" 2>/dev/null || true
  fi
done

# 如果链已存在则删除/清空
if iptables -L "$CHAIN" &>/dev/null; then
  iptables -F "$CHAIN" 2>/dev/null || true
  iptables -X "$CHAIN" 2>/dev/null || true
fi
if $IP6TABLES_AVAILABLE; then
  if ip6tables -L "$CHAIN" &>/dev/null; then
    ip6tables -F "$CHAIN" 2>/dev/null || true
    ip6tables -X "$CHAIN" 2>/dev/null || true
  fi
fi

iptables -N "$CHAIN" 2>/dev/null || true
if $IP6TABLES_AVAILABLE; then
  ip6tables -N "$CHAIN" 2>/dev/null || true
fi

# -----------------------
# 域名白名单（IPv4 + IPv6）
# -----------------------
if command -v dig >/dev/null 2>&1; then
  for d in "${DOMAINS[@]}"; do
    # IPv4
    # 注意：dig +short 可能返回多行
    for ip in $(dig +short A "$d" 2>/dev/null || true); do
      if [[ -n "$ip" ]]; then
        for p in "${PORTS[@]}"; do
          add_rule iptables -A "$CHAIN" -p tcp -s "$ip" --dport "$p" -j ACCEPT
        done
        echo "允许 IPv4 $ip ($d) 对端口 ${PORTS[*]}"
      fi
    done
    # IPv6（如果 ip6tables 可用）
    if $IP6TABLES_AVAILABLE; then
      for ip in $(dig +short AAAA "$d" 2>/dev/null || true); do
        if [[ -n "$ip" ]]; then
          for p in "${PORTS[@]}"; do
            add_rule ip6tables -A "$CHAIN" -p tcp -s "$ip" --dport "$p" -j ACCEPT
          done
          echo "允许 IPv6 $ip ($d) 对端口 ${PORTS[*]}"
        fi
      done
    fi
  done
else
  echo "跳过域名解析：dig 未安装"
fi

# -----------------------
# 固定 IP 段白名单（例如 39.0.0.0/8）
# -----------------------
for net in "${IP_WHITELIST[@]}"; do
  # 粗略检测是否以数字开头（IPv4 网段）
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
if $IP6TABLES_AVAILABLE; then
  add_rule ip6tables -A "$CHAIN" -j DROP
fi

# -----------------------
# INPUT 链处理：先删除可能残留的规则，然后插入我们需要的优先规则
# -----------------------
for p in "${PORTS[@]}"; do
  del_rule_if_exists iptables INPUT -i lo -p tcp --dport "$p" -j ACCEPT
  if $IP6TABLES_AVAILABLE; then
    del_rule_if_exists ip6tables INPUT -i lo -p tcp --dport "$p" -j ACCEPT
  fi
done

for net in "${LAN_NETS[@]}"; do
  for p in "${PORTS[@]}"; do
    del_rule_if_exists iptables INPUT -s "$net" -p tcp --dport "$p" -j ACCEPT
  done
done

for p in "${PORTS[@]}"; do
  del_rule_if_exists iptables INPUT -p tcp --dport "$p" -j "$CHAIN"
  if $IP6TABLES_AVAILABLE; then
    del_rule_if_exists ip6tables INPUT -p tcp --dport "$p" -j "$CHAIN"
  fi
done

# loopback 优先
for p in "${PORTS[@]}"; do
  add_rule iptables -I INPUT 1 -i lo -p tcp --dport "$p" -j ACCEPT
  if $IP6TABLES_AVAILABLE; then
    add_rule ip6tables -I INPUT 1 -i lo -p tcp --dport "$p" -j ACCEPT
  fi
  echo "已允许本地 loopback (127.0.0.1 / ::1) 访问端口 $p"
done

# 内网段优先（插入到 INPUT 第 2,3... 行）
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

# 挂接 SSH_RULES（最后把 INPUT 的相关端口流量引到我们新链）
for p in "${PORTS[@]}"; do
  add_rule iptables -A INPUT -p tcp --dport "$p" -j "$CHAIN"
  if $IP6TABLES_AVAILABLE; then
    add_rule ip6tables -A INPUT -p tcp --dport "$p" -j "$CHAIN"
  fi
done
echo "已挂接 $CHAIN 到 INPUT（公网连接经过 $CHAIN 判断） 对端口: ${PORTS[*]}"

# -----------------------
# 持久化保存（CentOS 7 适配）
# 优先顺序（尽量兼容各种安装）：
# 1) 如果存在 iptables-save/ip6tables-save -> 写入 /etc/sysconfig/iptables /etc/sysconfig/ip6tables
# 2) 如果存在 systemctl 且有 iptables.service -> 重启服务（iptables-services）
# 3) 兼容老方式 service iptables save
# -----------------------
SAVE_OK=false
if command -v iptables-save >/dev/null 2>&1; then
  echo "保存 IPv4 规则到 /etc/sysconfig/iptables"
  iptables-save > /etc/sysconfig/iptables || echo "写 /etc/sysconfig/iptables 失败（请检查权限）"
  SAVE_OK=true
fi

if $IP6TABLES_AVAILABLE && command -v ip6tables-save >/dev/null 2>&1; then
  echo "保存 IPv6 规则到 /etc/sysconfig/ip6tables"
  ip6tables-save > /etc/sysconfig/ip6tables || echo "写 /etc/sysconfig/ip6tables 失败（请检查权限）"
  SAVE_OK=true
fi

# 如果 systemctl 可用并且有 iptables 服务，则尝试重启以载入配置（适用于安装了 iptables-services 的情况）
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q "^iptables\\.service"; then
    echo "尝试通过 systemctl 重启 iptables.service 以应用持久化规则"
    systemctl restart iptables.service || echo "systemctl restart iptables 失败（如果未安装 iptables-services，请安装：yum install -y iptables-services）"
    systemctl enable iptables.service || true
    if $IP6TABLES_AVAILABLE; then
      if systemctl list-unit-files | grep -q "^ip6tables\\.service"; then
        systemctl restart ip6tables.service || true
        systemctl enable ip6tables.service || true
      fi
    fi
  fi
fi

# 兼容旧式 service save（如果存在）
if command -v service >/dev/null 2>&1 && [ -f /etc/init.d/iptables ]; then
  service iptables save || true
  SAVE_OK=true
fi

if [ "$SAVE_OK" = true ]; then
  echo "✅ 规则已尝试保存到系统持久化位置"
else
  echo "⚠️ 未检测到常用持久化方法（iptables-save / iptables-services / service iptables）；规则当前仅在内存中生效（重启后可能丢失）。"
  echo "建议在 CentOS 7 上安装 iptables-services 并使用 iptables-save："
  echo "  yum install -y iptables-services bind-utils"
  echo "  systemctl enable --now iptables"
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
  echo "未找到常见的认证日志文件（/var/log/auth.log 或 /var/log/secure）"
fi

echo
echo "🛡 当前 INPUT 规则（IPv4 前30行）："
iptables -L INPUT -n --line-numbers | sed -n '1,30p' || true

echo
echo "🛡 当前 $CHAIN 链规则（IPv4）："
iptables -L "$CHAIN" -n --line-numbers || true

if $IP6TABLES_AVAILABLE; then
  echo
  echo "🛡 当前 $CHAIN 链规则（IPv6）："
  ip6tables -L "$CHAIN" -n --line-numbers || true
fi

echo
echo "✅ 完成。已对端口 ${PORTS[*]} 应用规则。请确认 cloudflared 或其他代理服务绑定在本地端口（如有）。"
