# Shell Tools

Collection of shell scripts for various utilities.

## GitHub Runner Installation (ARM64)

This script automates the installation of self-hosted GitHub Runners on ARM64 (aarch64) Linux systems.

### Features
- **Auto-detection**: Automatically detects architecture and installs dependencies.
- **Interactive Configuration**: Prompts for Runner Name and Labels during setup.
- **Sudo Support**: Runs safely with `sudo` for privileged operations.
- **Service Management**: Automatically installs and starts the systemd service.

### Installation

**1. One-line Install (Recommended)**

Use the following command to download and run the script. It includes a cache-buster to ensure you get the latest version.

```bash
curl -fsSL "https://raw.githubusercontent.com/suwei8/sh_toos/main/install_gh_runner_arm64.sh?v=$(date +%s)" -o install_gh_runner_arm64.sh && chmod +x install_gh_runner_arm64.sh && ./install_gh_runner_arm64.sh --token YOUR_TOKEN
```

**2. Interactive Mode**

The script is pre-configured for `https://github.com/dianma365`. You only need to provide the token.
When the script asks for **Runner Name** or **Labels**, you can type them in.

```bash
./install_gh_runner_arm64.sh --token YOUR_TOKEN
```

**3. Custom Repository**

If you want to install for a different repository:

```bash
./install_gh_runner_arm64.sh https://github.com/your/repo --token YOUR_TOKEN
```

### Uninstallation

If you need to remove the runner (e.g., to rename it or clean up):

```bash
curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/main/uninstall_gh_runner_arm64.sh -o uninstall_gh_runner_arm64.sh && chmod +x uninstall_gh_runner_arm64.sh && ./uninstall_gh_runner_arm64.sh
```
> **Warning**: This will remove the runner service, user (`ghrunner`), and all local files in `/home/ghrunner`.

### x64 (Intel/AMD)
(Legacy script for x64 systems)
```bash
curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/main/install_gh_runner.sh -o install_gh_runner.sh && chmod +x install_gh_runner.sh && sudo ./install_gh_runner.sh
```
