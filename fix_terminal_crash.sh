#!/bin/bash
# ==============================================================================
# Script Name: fix_terminal_crash.sh
# Description: Fixes "Failed to execute default Terminal Emulator" (Input/output error)
#              on Ubuntu xRDP environments, specifically for xfce4-terminal.
# Author: Suwei8
# ==============================================================================
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check for root
if [[ $EUID -ne 0 ]]; then
   log_err "This script must be run as root" 
   exit 1
fi

log_info "Starting Terminal Crash Fix..."

# ==============================================================================
# 1. Fix Locales
# ==============================================================================
log_info "1. Fixing Locales..."
# Re-generate locales to ensure they exist
locale-gen en_US.UTF-8 zh_CN.UTF-8

# Clean up conflicting user config in typical locations
# (Loop through all users in /home)
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        user_name=$(basename "$user_home")
        log_info "Processing user: $user_name"
        
        # Remove hardcoded locale exports that might conflict
        if [ -f "$user_home/.bashrc" ]; then
            sed -i '/export LANG=/d' "$user_home/.bashrc"
            sed -i '/export LC_ALL=/d' "$user_home/.bashrc"
            sed -i '/export LANGUAGE=/d' "$user_home/.bashrc"
        fi
        if [ -f "$user_home/.profile" ]; then
            sed -i '/export LANG=/d' "$user_home/.profile"
            sed -i '/export LC_ALL=/d' "$user_home/.profile"
            sed -i '/export LANGUAGE=/d' "$user_home/.profile"
        fi
    fi
done

# Set system default to safe en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US:en
log_info "Locales regenerated and system default set to en_US.UTF-8."

# ==============================================================================
# 2. Fix Terminal Alternative & Dependencies
# ==============================================================================
log_info "2. Fixing Dependencies & Terminal Emulator Alternatives..."

# Ensure crucial dependencies are installed
log_info "Checking for dbus-x11 (required for xRDP sessions)..."
if ! dpkg -l | grep -q dbus-x11; then
    log_warn "dbus-x11 not found. Installing..."
    apt-get update -qq && apt-get install -y dbus-x11
fi

# Force x-terminal-emulator to xfce4-terminal.wrapper
# gnome-terminal often causes I/O errors in xRDP
if [ -f /usr/bin/xfce4-terminal.wrapper ]; then
    update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal.wrapper
    log_info "Set x-terminal-emulator to xfce4-terminal.wrapper"
elif [ -f /usr/bin/xfce4-terminal ]; then
    # Fallback if wrapper doesn't exist but binary does
    if ! update-alternatives --list x-terminal-emulator | grep -q "/usr/bin/xfce4-terminal"; then
        update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/xfce4-terminal 50
    fi
    update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal
    log_info "Set x-terminal-emulator to xfce4-terminal binary"
else
    log_warn "xfce4-terminal not found. Attempting to install..."
    apt-get update -qq && apt-get install -y xfce4-terminal
    
    if [ -f /usr/bin/xfce4-terminal.wrapper ]; then
        update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal.wrapper
        log_info "Installed xfce4-terminal and set alternative to wrapper."
    elif [ -f /usr/bin/xfce4-terminal ]; then
         # Fallback if wrapper missing after install
         update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/xfce4-terminal 50
         update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal
         log_info "Installed xfce4-terminal and set alternative to binary."
    else
        log_err "Failed to install xfce4-terminal. Please check internet connection."
    fi
fi

# Double check the result
CURRENT_ALT=$(update-alternatives --query x-terminal-emulator | grep 'Value:' | awk '{print $2}')
log_info "Current x-terminal-emulator points to: $CURRENT_ALT"

# ==============================================================================
# 3. Reset User Terminal Config
# ==============================================================================
log_info "3. Resetting User Terminal Config..."

for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        user_name=$(basename "$user_home")
        config_dir="$user_home/.config/xfce4/terminal"
        config_file="$config_dir/terminalrc"
        
        if [ -d "$user_home/.config" ]; then
            mkdir -p "$config_dir"
            
            # Write minimal safe config
            cat > "$config_file" << 'EOF'
[Configuration]
Encoding=UTF-8
EOF
            chown -R "$user_name:$user_name" "$user_home/.config"
            log_info "Reset terminalrc for user $user_name"
        fi
    fi
done

log_info "=========================================="
log_info "Fix Complete!"
log_info "Please logout and login again via xRDP."
log_info "=========================================="
