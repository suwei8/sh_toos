# Shell Tools

Collection of shell scripts for various utilities.

## GitHub Runner Installation (ARM64)

### Quick Start
```bash
curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/main/install_gh_runner_arm64.sh -o install_gh_runner_arm64.sh && chmod +x install_gh_runner_arm64.sh && ./install_gh_runner_arm64.sh --token YOUR_TOKEN
```

### Usage Options
The script is pre-configured for `https://github.com/dianma365`.

```bash
# Install with Token only (Recommended)
./install_gh_runner_arm64.sh --token A1B2C3D4E5

# Override URL if needed
./install_gh_runner_arm64.sh https://github.com/other/repo --token A1B2C3D4E5
```

### x64 (Intel/AMD)
(Standard legacy script)
```bash
curl -fsSL https://raw.githubusercontent.com/suwei8/sh_toos/main/install_gh_runner.sh -o install_gh_runner.sh && chmod +x install_gh_runner.sh && sudo ./install_gh_runner.sh
```
