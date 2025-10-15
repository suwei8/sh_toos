# sh_toos

## 1、cf-firewall.sh  
### 只允许 Cloudflare 的边缘节点访问你的服务器 80/443 端口
其他来源一律拒绝。这样所有访问必须走 Cloudflare，攻击者就没法绕过你设置的规则。
### 一键执行命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/cf-firewall.sh)
```

---


## 2、update-ssh-whitelist.sh
### 只允许 Cloudflare DDNS 子域名 动态白名单访问ssh
### Ubuntu一键执行命令：
```bash

sudo bash -c 'tmp=$(mktemp) && crontab -l 2>/dev/null | grep -Fv "curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/update-ssh-whitelist.sh | bash" >"$tmp" || true; echo "*/5 * * * * /bin/bash -c '\''curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/update-ssh-whitelist.sh | bash'\''" >>"$tmp"; crontab "$tmp"; rm -f "$tmp"; /bin/bash -c '\''curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/update-ssh-whitelist.sh | bash'\'''

```

### CentOS7一键执行命令：

```bash

sudo bash -c 'tmp=$(mktemp) && crontab -l 2>/dev/null | grep -Fv "curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/update-ssh-whitelist-CentOS7.sh | bash" >"$tmp" || true; echo "*/5 * * * * /bin/bash -c '\''curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/update-ssh-whitelist-CentOS7.sh | bash'\''" >>"$tmp"; crontab "$tmp"; rm -f "$tmp"; /bin/bash -c '\''curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/update-ssh-whitelist-CentOS7.sh | bash'\'''

```

### alpine3.20一键执行命令：

```bash

sh -c 'apk add --no-cache wget busybox-extras openrc >/dev/null; tmp=$(mktemp); crontab -l 2>/
dev/null | grep -Fv "wget --no-cache -qO- https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/
update-ssh-whitelist-alpine.sh | sh" >"$tmp" || true; echo "*/5 * * * * /bin/sh -c '\''wget --no-cache -qO-
 https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/update-ssh-whitelist-alpine.sh | sh'\''"
>>"$tmp"; crontab "$tmp"; rm -f "$tmp"; rc-update add crond default; service crond start; /bin/sh -c '\''wg
et --no-cache -qO- https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/update-ssh-whitelist-al
pine.sh | sh'\'''


```


### 查看定时任务

```bash

crontab -e

```

### 本机外网ip
```bash
curl ifconfig.me
```

