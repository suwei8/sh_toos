#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
RUNNER_USER="ghrunner"
RUNNER_HOME="/home/${RUNNER_USER}"
RUNNER_DIR="${RUNNER_HOME}/actions-runner"
SUDO_CMD=""

# ==============================================================================
# Helper Functions
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        SUDO_CMD=""
    elif command -v sudo &> /dev/null; then
        SUDO_CMD="sudo"
    else
        log_err "This script requires root privileges or sudo access."
        exit 1
    fi
}

uninstall_service() {
    log_info "Stopping and removing systemd service..."
    if [[ -d "${RUNNER_DIR}" ]]; then
        cd "${RUNNER_DIR}"
        if [[ -f "./svc.sh" ]]; then
            $SUDO_CMD ./svc.sh stop || log_warn "Service could not be stopped (maybe not running)."
            $SUDO_CMD ./svc.sh uninstall || log_warn "Service could not be uninstalled (maybe not installed)."
        else
            log_warn "svc.sh not found. Skipping service uninstall via script."
        fi
    else
        log_warn "Runner directory not found. Skipping service removal."
    fi
}

remove_runner_config() {
    log_info "Removing runner configuration..."
    if [[ -d "${RUNNER_DIR}" ]]; then
        # Check if we have a token to strictly unregister?
        # Usually 'config.sh remove' requires a token.
        # If user just wants to clean up local files to re-install, we can skip strict unregister 
        # OR verify if they provided a token.
        
        # If we just delete files, the runner stays "Offline" in GitHub UI until manually removed.
        # This is often acceptable for "Re-install on same machine" scenarios.
        
        log_warn "This script removes LOCAL files and services."
        log_warn "You may need to manually remove the runner from GitHub Settings > Actions > Runners to clean up the UI."
        
        log_info "Removing directory ${RUNNER_DIR}..."
        $SUDO_CMD rm -rf "${RUNNER_DIR}"
    fi
}

remove_user() {
    log_info "Removing runner user '${RUNNER_USER}'..."
    if id "${RUNNER_USER}" &>/dev/null; then
        $SUDO_CMD userdel -r "${RUNNER_USER}" || log_warn "Failed to remove user (processes might be running?)"
    else
        log_info "User '${RUNNER_USER}' does not exist."
    fi
}

# ==============================================================================
# Main
# ==============================================================================
check_privileges

echo -e "${YELLOW}WARNING: This will completely remove the runner service, user, and files.${NC}"
read -rp "Are you sure you want to continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

uninstall_service
remove_runner_config
remove_user

log_info "Uninstallation complete. You can now re-install."
