# Shell Tools

各种实用 Shell 脚本的集合。

## GitHub Runner Installation (ARM64)

此脚本用于在 ARM64 (aarch64) Linux 系统上自动安装自托管 GitHub Runner。

### 功能特点
- **自动检测**: 自动检测系统架构并安装依赖项。
- **交互式配置**: 安装过程中提示输入 Runner 名称和标签。
- **Sudo 支持**: 通过 `sudo` 安全运行特权操作。
- **服务管理**: 自动安装并启动 systemd 服务。

### 安装方法

**1. 一键安装 (推荐)**

使用以下命令下载并运行脚本。该命令包含防缓存参数，确保下载到最新版本。

```bash
curl -fsSL "https://raw.githubusercontent.com/suwei8/sh_toos/main/install_gh_runner_arm64.sh?v=$(date +%s)" -o install_gh_runner_arm64.sh && chmod +x install_gh_runner_arm64.sh && ./install_gh_runner_arm64.sh --token YOUR_TOKEN
```

**2. 交互模式**

脚本已预配置仓库 `https://github.com/dianma365`。您只需提供 Token。
当脚本询问 **Runner Name** 或 **Labels** 时，您可以手动输入。

```bash
./install_gh_runner_arm64.sh --token YOUR_TOKEN
```

**3. 自定义仓库**

如果您需要为其他仓库安装 Runner：

```bash
./install_gh_runner_arm64.sh https://github.com/your/repo --token YOUR_TOKEN
```

### 卸载

如果需要移除 Runner (例如重命名或清理环境)：

```bash
curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/main/uninstall_gh_runner_arm64.sh -o uninstall_gh_runner_arm64.sh && chmod +x uninstall_gh_runner_arm64.sh && ./uninstall_gh_runner_arm64.sh
```
> **警告**: 此操作将删除 runner 服务、用户 (`ghrunner`) 以及 `/home/ghrunner` 目录下的所有文件。

### x64 (Intel/AMD)
(适用于 x64 系统的旧版脚本)
```bash
curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/main/install_gh_runner.sh -o install_gh_runner.sh && chmod +x install_gh_runner.sh && sudo ./install_gh_runner.sh
```

---

## Remote Dev Environment Setup (ARM64)

全自动远程开发环境部署脚本，适用于 Oracle Cloud VM.Standard.A1.Flex (ARM64) + Ubuntu 20.04 系统。

### 功能特点

一键部署完整的远程开发环境，包括：
- **用户配置**: 创建用户 `sw`，配置免密 sudo
- **中文支持**: 安装中文语言包和字体
- **桌面环境**: XFCE + LightDM 最小化桌面
- **远程访问**: xRDP（含 Chromium snap 兼容修复）
- **浏览器**: Chromium (via snap，ARM64 兼容)
- **开发工具**: Docker + Compose, Node.js (via nvm v24)
- **AI 工具**: gemini-cli, Google Antigravity, Codex CLI
- **网络工具**: cloudflared (Cloudflare Tunnel)
- **版本控制**: Git 配置 + SSH 密钥生成

### 安装方法

**一键安装 (推荐)**

```bash
curl -fsSL "https://raw.githubusercontent.com/suwei8/sh_toos/main/setup_remote_dev_env.sh?v=$(date +%s)" -o setup_remote_dev_env.sh && chmod +x setup_remote_dev_env.sh && sudo ./setup_remote_dev_env.sh
```

### 重要说明

> ⚠️ **Chromium 兼容性**: 脚本已包含 xRDP 会话中 Chromium snap 正常启动所需的 DBUS 环境变量修复。

> ⚠️ **xRDP 端口**: 默认配置为 `127.0.0.1:3389`，请通过 Cloudflare Tunnel 进行远程访问。

### 环境要求

- **架构**: ARM64 (aarch64)
- **系统**: Ubuntu 20.04 LTS
- **权限**: root 或 sudo

---

## Restrict SSH to Localhost

限制 SSH 服务只监听本地端口（127.0.0.1），阻止外部直接访问，只允许通过 Cloudflare Tunnel 连接。

### 功能特点

- **安全增强**: SSH 仅监听 `127.0.0.1`，外部无法直接连接
- **自动检测**: 检查配置是否已存在，避免重复添加
- **多发行版兼容**: 支持 Ubuntu (ssh) 和 CentOS/RHEL (sshd) 服务名称
- **自动验证**: 执行后自动显示监听端口状态

### 安装方法

**一键执行 (推荐)**

```bash
curl -fsSL "https://raw.githubusercontent.com/suwei8/sh_toos/main/restrict_ssh_localhost.sh?v=$(date +%s)" -o restrict_ssh_localhost.sh && chmod +x restrict_ssh_localhost.sh && sudo ./restrict_ssh_localhost.sh
```

### 重要说明

> ⚠️ **警告**: 执行此脚本后，外部 SSH 连接将被阻止！请确保 Cloudflare Tunnel 已正确配置并测试通过后再执行。

> 💡 **工作原理**: 脚本在 `/etc/ssh/sshd_config` 中添加 `ListenAddress 127.0.0.1`，使 SSH 服务仅监听本地回环地址。

---

## Repair Terminal Encoding

如果您的终端出现中文乱码（尤其是在 xRDP 环境下），请运行此修复脚本。

### 功能特点

- **强制 UTF-8**: 配置系统 Locale 和 xfce4-terminal 强制使用 UTF-8 编码。
- **一键修复**: 自动生成 Locales 并更新用户配置文件。

### 使用方法

```bash
curl -fsSL "https://raw.githubusercontent.com/suwei8/sh_toos/main/repair_terminal_encoding.sh?v=$(date +%s)" -o repair.sh && sudo bash repair.sh
```
