#!/bin/bash
# ==============================================================================
# Script Name: fix_chromium_snap.sh
# Description: Fixes Chromium Snap launch issues in xRDP on Ubuntu 20.04
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

if [[ $EUID -ne 0 ]]; then
   log_err "This script must be run as root" 
   exit 1
fi

log_info "Starting Chromium Snap Fix..."

# 1. Rewrite startwm.sh with a stable runtime-dir fix
STARTWM="/etc/xrdp/startwm.sh"
if [ -f "$STARTWM" ]; then
    log_info "Rewriting $STARTWM..."
    cat > "$STARTWM" << 'EOF'
#!/bin/sh
if test -r /etc/profile; then . /etc/profile; fi
if test -r /etc/default/locale; then . /etc/default/locale; fi

uid="$(id -u)"
gid="$(id -g)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"

if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    sudo install -d -m 700 -o "$uid" -g "$gid" "$XDG_RUNTIME_DIR"
else
    owner_uid="$(stat -c '%u' "$XDG_RUNTIME_DIR" 2>/dev/null || echo '')"
    owner_gid="$(stat -c '%g' "$XDG_RUNTIME_DIR" 2>/dev/null || echo '')"
    perms="$(stat -c '%a' "$XDG_RUNTIME_DIR" 2>/dev/null || echo '')"
    if [ "$owner_uid" != "$uid" ] || [ "$owner_gid" != "$gid" ] || [ "$perms" != "700" ]; then
        sudo chown "$uid:$gid" "$XDG_RUNTIME_DIR"
        sudo chmod 700 "$XDG_RUNTIME_DIR"
    fi
fi

exec startxfce4
EOF
    chmod +x "$STARTWM"
else
    log_err "$STARTWM not found!"
fi

# 2. Create wrapper
WRAPPER="/usr/local/bin/chromium-snap"
log_info "Creating wrapper at $WRAPPER..."

cat > "$WRAPPER" << 'EOF'
#!/bin/bash
# Chromium wrapper for snap on Ubuntu 20.04
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
    echo "XDG_RUNTIME_DIR does not exist: $XDG_RUNTIME_DIR" >&2
    exit 1
fi

exec /snap/bin/chromium "$@"
EOF
chmod +x "$WRAPPER"

# 3. Update Alternatives (Optional but good)
log_info "Updating alternatives..."
update-alternatives --install /usr/bin/x-www-browser x-www-browser "$WRAPPER" 200
update-alternatives --set x-www-browser "$WRAPPER"
update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser "$WRAPPER" 200
update-alternatives --set gnome-www-browser "$WRAPPER"

# 4. Override the desktop launcher for existing users
if [ -f /var/lib/snapd/desktop/applications/chromium_chromium.desktop ]; then
    for user_home in /home/*; do
        [ -d "$user_home" ] || continue
        user_name=$(basename "$user_home")
        desktop_dir="$user_home/.local/share/applications"
        install -d -m 755 -o "$user_name" -g "$user_name" "$desktop_dir"
        sed 's#^Exec=/snap/bin/chromium#Exec=/usr/local/bin/chromium-snap#' \
            /var/lib/snapd/desktop/applications/chromium_chromium.desktop \
            > "$desktop_dir/chromium_chromium.desktop"
        chown "$user_name:$user_name" "$desktop_dir/chromium_chromium.desktop"
    done
fi

log_info "=========================================="
log_info "Fix Complete!"
log_info "Please logout and login again via xRDP."
log_info "Try launching Chromium via command: chromium-snap"
log_info "=========================================="
