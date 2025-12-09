# Shell Tools

Collection of shell scripts for various utilities.

## GitHub Runner Installation

### x64 (Intel/AMD)
```bash
curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/main/install_gh_runner.sh -o install_gh_runner.sh && chmod +x install_gh_runner.sh && sudo ./install_gh_runner.sh
```

### ARM64 (aarch64)
**One-line installation:**
```bash
curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/main/install_gh_runner_arm64.sh -o install_gh_runner_arm64.sh && chmod +x install_gh_runner_arm64.sh && ./install_gh_runner_arm64.sh
```

**Usage with arguments:**
```bash
./install_gh_runner_arm64.sh [REPO_URL] [--token TOKEN]

# Example
./install_gh_runner_arm64.sh https://github.com/user/repo --token A1B2C3D4E5
```
