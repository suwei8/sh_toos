#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
# Default Configuration
REPO_URL=""
RUNNER_TOKEN=""

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --token)
            RUNNER_TOKEN="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [REPO_URL] [--token TOKEN]"
            exit 0
            ;;
        *)
            if [[ -z "$REPO_URL" ]]; then
                REPO_URL="$1"
            else
                echo "Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Hardcode Default URL if not provided
if [[ -z "$REPO_URL" ]]; then
    REPO_URL="https://github.com/dianma365"
fi

RUNNER_USER="ghrunner"
RUNNER_HOME="/home/${RUNNER_USER}"
RUNNER_DIR="${RUNNER_HOME}/actions-runner"
RUNNER_ARCH="arm64" 
SUDO_CMD=""

# ==============================================================================
# Helper Functions
# ==============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        SUDO_CMD=""
    elif command -v sudo &> /dev/null; then
        SUDO_CMD="sudo"
        # Validate sudo access
        if ! sudo -n true 2>/dev/null; then
            log_warn "Sudo password may be required."
            sudo true
        fi
    else
        log_err "This script requires root privileges or sudo access."
        exit 1
    fi
}

check_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        aarch64|arm64)
            log_info "Detected ARM64 architecture ($arch)."
            ;;
        *)
            log_err "Architecture $arch is not supported. This script is for ARM64 only."
            exit 1
            ;;
    esac
}

install_dependencies() {
    log_info "Checking and installing dependencies..."
    local deps=(curl jq tar)
    # Check if we need to install anything
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Installing missing dependencies: ${missing[*]}"
        $SUDO_CMD apt-get update -qq
        $SUDO_CMD apt-get install -y "${missing[@]}"
    fi
}

get_input() {
    # If variables are not set, prompt user
    if [[ -z "$REPO_URL" ]]; then
        read -rp "Enter GitHub Repository URL (e.g., https://github.com/user/repo): " REPO_URL
    fi

    if [[ -z "$RUNNER_TOKEN" ]]; then
        read -rp "Enter GitHub Runner Registration Token: " RUNNER_TOKEN
    fi

    if [[ -z "$REPO_URL" || -z "$RUNNER_TOKEN" ]]; then
        log_err "Repository URL and Token are required."
        exit 1
    fi
}

get_latest_version() {
    # log_info "Fetching latest GitHub Runner version..." >&2
    local api_url="https://api.github.com/repos/actions/runner/releases/latest"
    local version_tag
    
    # Attempt to fetch latest version
    if version_tag=$(curl -s "$api_url" | jq -r .tag_name | sed 's/^v//'); then
        if [[ "$version_tag" == "null" || -z "$version_tag" ]]; then
             # log_warn "Could not fetch latest version (API limitation). Using default." >&2
             version_tag="2.321.0"
        fi
    else
        # log_warn "Failed to query GitHub API. Using default version." >&2
        version_tag="2.321.0"
    fi
    
    # log_info "Target runner version: $version_tag" >&2
    echo "$version_tag"
}

create_system_user() {
    log_info "Ensuring runner user '${RUNNER_USER}' exists..."
    if ! id "${RUNNER_USER}" &>/dev/null; then
        $SUDO_CMD useradd -m -s /bin/bash "${RUNNER_USER}"
        # Lock password for security (service account)
        # $SUDO_CMD passwd -l "${RUNNER_USER}" 
        
        # Add to sudo group if needed (optional, usually safer NOT to, but user might need it for workflows)
        # Uncomment below if runner needs sudo
        $SUDO_CMD usermod -aG sudo "${RUNNER_USER}"
        
        # Ensure 'sudo' allows this user to run without password? 
        # Usually we don't want to modify sudoers automatically without asking.
        
        log_info "User ${RUNNER_USER} created."
    else
        log_info "User ${RUNNER_USER} already exists."
    fi
}

setup_directory() {
    log_info "Preparing directory: ${RUNNER_DIR}"
    if [[ ! -d "${RUNNER_DIR}" ]]; then
        $SUDO_CMD mkdir -p "${RUNNER_DIR}"
    fi
    $SUDO_CMD chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_HOME}"
}

install_runner_binaries() {
    local version="$1"
    local runner_file="actions-runner-linux-${RUNNER_ARCH}-${version}.tar.gz"
    local download_url="https://github.com/actions/runner/releases/download/v${version}/${runner_file}"

    # Verify if already installed
    if [[ -f "${RUNNER_DIR}/config.sh" ]]; then
        log_info "Runner binaries appear to be present."
        return
    fi
    
    log_info "Downloading runner binaries..."
    
    # Download as the runner user to avoid permission issues later, or just fix permissions after
    # Using runuser/sudo to do it as the user is cleaner
    $SUDO_CMD -u "${RUNNER_USER}" bash -c "
        cd '${RUNNER_DIR}'
        if [[ ! -f '${runner_file}' ]]; then
            curl -o '${runner_file}' -L '${download_url}'
        fi
        echo 'Extracting...'
        tar xzf '${runner_file}'
    "
}

configure_runner() {
    if [[ -f "${RUNNER_DIR}/.runner" ]]; then
        log_warn "Runner is already configured. Skipping configuration."
        return
    fi

    log_info "Configuring runner..."
    $SUDO_CMD -u "${RUNNER_USER}" "${RUNNER_DIR}/config.sh" \
        --url "${REPO_URL}" \
        --token "${RUNNER_TOKEN}" \
        --replace
}

install_service() {
    log_info "Installing and starting systemd service..."
    cd "${RUNNER_DIR}"
    
    # Use the svc.sh script provided by the runner
    # It must be run with sudo/root
    $SUDO_CMD ./svc.sh install "${RUNNER_USER}" || true # Ignore if already registered
    $SUDO_CMD ./svc.sh start || echo "Service might already be running."
    $SUDO_CMD ./svc.sh status
}

# ==============================================================================
# Main Execution
# ==============================================================================

check_privileges
check_arch
install_dependencies
get_input


VERSION=$(get_latest_version)

# Sanity check validation to prevent capturing logs (defensive coding)
if [[ "$VERSION" == *"[INFO]"* ]] || [[ "$VERSION" == *"[WARN]"* ]] || [[ -z "$VERSION" ]]; then
    log_warn "Version detection returned unexpected output: $VERSION"
    log_warn "Falling back to default stable version."
    VERSION="2.321.0"
else
    # clean up any whitespace
    VERSION=$(echo "$VERSION" | tr -d '[:space:]')
fi


create_system_user
setup_directory
install_runner_binaries "$VERSION"
configure_runner
install_service

log_info "Installation and setup complete!"
