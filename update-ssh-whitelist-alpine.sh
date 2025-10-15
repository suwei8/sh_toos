#!/bin/sh
export PATH=/sbin:/usr/sbin:/usr/bin:/bin
set -eu


# ===========================================================
# 高安全 SSH 防护脚本（适配 Alpine 3.20）
# 版本：v2.2-alpine（自动安装依赖）
# ===========================================================

PORTS="22 2053"

DOMAINS="
ssh-mobile-v4.555606.xyz
wky.555606.xyz
ssh-vps-v4.555606.xyz
ssh-vps-v6.555606.xyz
"

LAN_NETS="
10.0.0.0/16
"

IP_WHITELIST="
39.0.0.0/8
"

CHAIN="SSH_RULES"

# -----------------------
# 环境检查 & 自动安装依赖
# -----------------------
echo "🔍 检查依赖..."

# 检查包管理器
if ! command -v apk >/dev/null 2>&1; then
  echo "❌ 未检测到 apk 包管理器，本脚本仅支持 Alpine Linux"
  exit 1
fi

# 检查并安装 iptables/ip6tables
need_install=""
for cmd in iptables ip6tables; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    need_install="1"
  fi
done

if [ -n "$need_install" ]; then
  echo "⚙️ 正在安装 iptables 组件..."
  apk add --no-cache iptables ip6tables >/dev/null
  echo "✅ iptables 已安装完成。"
fi

# 检查 dig（用于域名白名单）
if ! command -v dig >/dev/null 2>&1; then
  echo "⚙️ 正在安装 bind-tools（提供 dig）..."
  apk add --no-cache bind-tools >/dev/null || echo "⚠️ 无法安装 bind-tools，域名解析将被跳过"
fi

# -----------------------
# 清理旧链
# -----------------------
for p in $PORTS; do
  iptables -D INPUT -p tcp --dport "$p" -j "$CHAIN" 2>/dev/null || true
  ip6tables -D INPUT -p tcp --dport "$p" -j "$CHAIN" 2>/dev/null || true
done

if iptables -L "$CHAIN" >/dev/null 2>&1; then
  iptables -F "$CHAIN" && iptables -X "$CHAIN"
fi
if ip6tables -L "$CHAIN" >/dev/null 2>&1; then
  ip6tables -F "$CHAIN" && ip6tables -X "$CHAIN"
fi

iptables -N "$CHAIN" 2>/dev/null || true
ip6tables -N "$CHAIN" 2>/dev/null || true

# -----------------------
# 域名白名单
# -----------------------
if command -v dig >/dev/null 2>&1; then
  for d in $DOMAINS; do
    # IPv4
    for ip in $(dig +short A "$d" 2>/dev/null); do
      for p in $PORTS; do
        iptables -A "$CHAIN" -p tcp -s "$ip" --dport "$p" -j ACCEPT
      done
      echo "允许 IPv4 $ip ($d) 对端口 $PORTS"
    done
    # IPv6
    for ip in $(dig +short AAAA "$d" 2>/dev/null); do
      for p in $PORTS; do
        ip6tables -A "$CHAIN" -p tcp -s "$ip" --dport "$p" -j ACCEPT
      done
      echo "允许 IPv6 $ip ($d) 对端口 $PORTS"
    done
  done
else
  echo "⚠️ 跳过域名白名单：dig 未安装"
fi

# -----------------------
# 固定 IP 段白名单
# -----------------------
for net in $IP_WHITELIST; do
  for p in $PORTS; do
    iptables -A "$CHAIN" -p tcp -s "$net" --dport "$p" -j ACCEPT
    echo "允许固定 IPv4 段 $net 访问端口 $p"
  done
done

# -----------------------
# 默认 DROP（非白名单丢弃）
# -----------------------
iptables -A "$CHAIN" -j DROP
ip6tables -A "$CHAIN" -j DROP

# -----------------------
# loopback 和内网允许
# -----------------------
for p in $PORTS; do
  iptables -I INPUT -i lo -p tcp --dport "$p" -j ACCEPT
  ip6tables -I INPUT -i lo -p tcp --dport "$p" -j ACCEPT
  echo "允许 loopback (127.0.0.1 / ::1) 访问端口 $p"
done

for net in $LAN_NETS; do
  for p in $PORTS; do
    iptables -I INPUT 2 -s "$net" -p tcp --dport "$p" -j ACCEPT
    echo "允许内网网段 $net 访问端口 $p"
  done
done

# -----------------------
# 挂接 SSH_RULES 链
# -----------------------
for p in $PORTS; do
  iptables -A INPUT -p tcp --dport "$p" -j "$CHAIN"
  ip6tables -A INPUT -p tcp --dport "$p" -j "$CHAIN"
done
echo "✅ 已挂接 $CHAIN 到 INPUT，对端口: $PORTS"

# -----------------------
# 持久化保存
# -----------------------
if command -v rc-service >/dev/null 2>&1; then
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules-save
  ip6tables-save > /etc/iptables/rules6-save
  echo "✅ 规则已保存到 /etc/iptables/rules-save"
  echo '#!/bin/sh' > /etc/local.d/iptables.start
  echo 'iptables-restore < /etc/iptables/rules-save' >> /etc/local.d/iptables.start
  echo 'ip6tables-restore < /etc/iptables/rules6-save' >> /etc/local.d/iptables.start
  chmod +x /etc/local.d/iptables.start
  rc-update add local default
  echo "✅ 规则将开机自动恢复"
else
  echo "⚠️ 无持久化支持，规则将在重启后丢失"
fi

# -----------------------
# 状态输出
# -----------------------
echo
echo "🛡 当前 INPUT 链前 30 行："
iptables -L INPUT -n --line-numbers | head -n 30

echo
echo "🛡 $CHAIN 链规则（IPv4）："
iptables -L "$CHAIN" -n --line-numbers

echo
echo "🛡 $CHAIN 链规则（IPv6）："
ip6tables -L "$CHAIN" -n --line-numbers

echo
echo "✅ SSH 防护规则已部署完成。"
