# Download and install nvm:
`curl -o- https://gh-proxy.555606.xyz/https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/Node/install.sh | bash`

# in lieu of restarting the shell
`\. "$HOME/.nvm/nvm.sh"`




### ✅ 使用国内镜像（推荐）

执行以下命令（一次即可），让 nvm 使用淘宝镜像：

```bash
export NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node/
```

然后重新执行：

```bash
nvm install 22
```

👉 它就会从 **阿里 npm 镜像源（npmmirror.com）** 下载 Node.js，速度会非常快。

为了永久生效，可以把上面的环境变量加进 `~/.bashrc`：

```bash
echo 'export NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node/' >> ~/.bashrc
source ~/.bashrc
```

---

## 🔍 三、验证是否正常

执行：

```bash
nvm ls-remote | tail -10
```

若输出类似：

```
       v21.6.2
       v21.7.1
       v22.0.0
       v22.1.0
       v22.2.0
```

说明镜像配置已生效 ✅

---


# Verify the Node.js version:
`node -v` # Should print "v22.20.0".

# Verify npm version:
`npm -v` # Should print "10.9.3".
