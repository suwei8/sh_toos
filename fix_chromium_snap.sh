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

# 1. Fix startwm.sh
# Ensure 'xhost +si:localuser:$(whoami)' is present
STARTWM="/etc/xrdp/startwm.sh"
if [ -f "$STARTWM" ]; then
    log_info "Checking $STARTWM..."
    
    if ! grep -q "xhost +si:localuser" "$STARTWM"; then
        log_info "Adding 'xhost +si:localuser:\$(whoami)' to $STARTWM..."
        # Insert before startxfce4
        sed -i '/startxfce4/i xhost +si:localuser:$(whoami)' "$STARTWM"
    else
        log_info "'xhost +si:localuser' already present in $STARTWM"
    fi
    
    # Ensure unsets are present
    if ! grep -q "unset DBUS_SESSION_BUS_ADDRESS" "$STARTWM"; then
        sed -i '2i unset DBUS_SESSION_BUS_ADDRESS' "$STARTWM"
    fi
    if ! grep -q "unset XDG_RUNTIME_DIR" "$STARTWM"; then
        sed -i '3i unset XDG_RUNTIME_DIR' "$STARTWM"
    fi
else
    log_err "$STARTWM not found!"
fi

# 2. Create Wrapper (Double safety)
WRAPPER="/usr/local/bin/chromium-snap"
log_info "Creating wrapper at $WRAPPER..."

cat > "$WRAPPER" << 'EOF'
#!/bin/bash
# Chromium wrapper for snap on Ubuntu 20.04
# This wrapper explicitly unsets variables even if startwm.sh missed it
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec /snap/bin/chromium "$@"
EOF
chmod +x "$WRAPPER"

# 3. Update Alternatives (Optional but good)
log_info "Updating alternatives..."
update-alternatives --install /usr/bin/x-www-browser x-www-browser "$WRAPPER" 200
update-alternatives --set x-www-browser "$WRAPPER"
update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser "$WRAPPER" 200
update-alternatives --set gnome-www-browser "$WRAPPER"

log_info "=========================================="
log_info "Fix Complete!"
log_info "Please logout and login again via xRDP."
log_info "Try launching Chromium via command: chromium-snap"
log_info "=========================================="
