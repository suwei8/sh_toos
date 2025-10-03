#!/bin/bash
set -euo pipefail

# -----------------------
# 配置
# -----------------------
PORT=22
# 请在这里填写你要白名单的域名（保持原有逻辑）
DOMAINS=(
  ssh-mobile-v4.555606.xyz
  wky.555606.xyz
  ssh-vps-v4.555606.xyz
  ssh-vps-v6.555606.xyz
)

# 允许的局域网网段 (IPv4)。按需修改。例如: 10.0.0.0/16 或 10.0.1.0/24
LAN_NET="10.0.0.0/16"

# 链名
CHAIN="SSH_RULES"

# -----------------------
# 前置检查
# -----------------------
command -v iptables >/dev/null 2>&1 || { echo "iptables 未安装或不可用"; exit 1; }
command -v ip6tables >/dev/null 2>&1 || { echo "ip6tables 未安装或不可用"; exit 1; }
command -v dig >/dev/null 2>&1 || { echo "dig 未检测到，建议安装 bind9-dnsutils 或 dnsutils"; }

# -----------------------
# 清理旧链和挂载点
# -----------------------
# 如果之前有挂接，先尝试删除（忽略错误）
iptables -D INPUT -p tcp --dport "$PORT" -j "$CHAIN" 2>/dev/null || true
ip6tables -D INPUT -p tcp --dport "$PORT" -j "$CHAIN" 2>/dev/null || true

# flush & delete old chains if exist
iptables -F "$CHAIN" 2>/dev/null || true
ip6tables -F "$CHAIN" 2>/dev/null || true
iptables -X "$CHAIN" 2>/dev/null || true
ip6tables -X "$CHAIN" 2>/dev/null || true

# create new chains
iptables -N "$CHAIN"
ip6tables -N "$CHAIN"

# -----------------------
# 在 SSH_RULES 链中添加白名单（基于域名解析结果）
# -----------------------
for d in "${DOMAINS[@]}"; do
  # IPv4
  if command -v dig >/dev/null 2>&1; then
    for ip in $(dig +short A "$d"); do
      if [[ -n "$ip" ]]; then
        iptables -A "$CHAIN" -p tcp -s "$ip" --dport "$PORT" -j ACCEPT
        echo "允许 IPv4 $ip ($d)"
      fi
    done
    # IPv6
    for ip in $(dig +short AAAA "$d"); do
      if [[ -n "$ip" ]]; then
        ip6tables -A "$CHAIN" -p tcp -s "$ip" --dport "$PORT" -j ACCEPT
        echo "允许 IPv6 $ip ($d)"
      fi
    done
  else
    echo "warning: dig 未安装，跳过解析 $d"
  fi
done

# -----------------------
# 在链尾默认 DROP（阻止未在白名单的直连公网 SSH）
# -----------------------
iptables -A "$CHAIN" -j DROP
ip6tables -A "$CHAIN" -j DROP

# -----------------------
# 应用到 INPUT 链：
# 先插入：允许本地 loopback（cloudflared 需要）
#            允许内网网段 (IPv4)
# 再挂接 SSH_RULES 链（把 SSH_RULES 放在 INPUT 的前面判断）
# -----------------------

# 删除可能存在的老规则（容错）
iptables -D INPUT -i lo -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || true
ip6tables -D INPUT -i lo -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || true
iptables -D INPUT -s "$LAN_NET" -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || true
# note: 不对 IPv6 添加 10.0.x.x 规则（这是 IPv4 地址）

# 1) 允许本地 loopback (cloudflared -> local ssh)
iptables -I INPUT -i lo -p tcp --dport "$PORT" -j ACCEPT
ip6tables -I INPUT -i lo -p tcp --dport "$PORT" -j ACCEPT
echo "已允许本地 loopback (127.0.0.1 / ::1) 访问端口 $PORT"

# 2) 允许内网网段 IPv4
# 仅当 LAN_NET 非空且看起来像 IPv4 CIDR 时才添加
if [[ -n "$LAN_NET" ]]; then
  # 简单校验（以数字开头）
  if [[ "$LAN_NET" =~ ^[0-9] ]]; then
    iptables -I INPUT -s "$LAN_NET" -p tcp --dport "$PORT" -j ACCEPT
    echo "已允许内网网段 $LAN_NET 访问端口 $PORT"
  else
    echo "跳过 LAN_NET: 格式疑似不为 IPv4 CIDR ($LAN_NET)"
  fi
fi

# 3) 把 SSH_RULES 链挂到 INPUT（放在后面）
iptables -I INPUT -p tcp --dport "$PORT" -j "$CHAIN"
ip6tables -I INPUT -p tcp --dport "$PORT" -j "$CHAIN"
echo "已挂接 $CHAIN 到 INPUT（所有外部 IPv4/IPv6 SSH 连接将先过 $CHAIN 判断）"

# -----------------------
# 保存规则（Debian/Ubuntu 上使用 netfilter-persistent）
# -----------------------
if ! command -v netfilter-persistent >/dev/null 2>&1; then
  if [ -f /etc/debian_version ]; then
    echo "未检测到 netfilter-persistent，尝试安装（需要 root 并联网）..."
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent || true
  fi
fi

if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save || echo "保存规则到 netfilter-persistent 失败"
  echo "✅ 规则已保存到 netfilter-persistent"
elif command -v service >/dev/null 2>&1 && [ -f /etc/init.d/iptables ]; then
  service iptables save || true
  echo "✅ 规则已保存到 /etc/init.d/iptables"
else
  echo "⚠️ 未检测到规则保存工具，规则只在当前会话生效（重启后会丢失）"
fi

# -----------------------
# 日志与状态查看（可选）
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
echo "🛡 当前 IPv4 $CHAIN 规则："
iptables -L "$CHAIN" -n --line-numbers || true

echo
echo "🛡 当前 IPv6 $CHAIN 规则："
ip6tables -L "$CHAIN" -n --line-numbers || true

# -----------------------
# （可选）清理认证日志 - 若你确实需要可以打开（此处注释掉，防止误删）
# -----------------------
# echo
# echo "🧹 清理认证日志..."
# if [ -f /var/log/auth.log ]; then
#   truncate -s 0 /var/log/auth.log
#   echo "✅ 已清空 /var/log/auth.log"
# elif [ -f /var/log/secure ]; then
#   truncate -s 0 /var/log/secure
#   echo "✅ 已清空 /var/log/secure"
# fi

echo
echo "完成。请确认 cloudflared 服务正在运行并绑定到本地 (127.0.0.1) 或相应端口。"
