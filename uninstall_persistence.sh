#!/bin/bash
# uninstall_persistence.sh
set -e

echo "🗑  Uninstalling Maharnet 5G Tuning..."

# 1. Remove Sysctl
SYSCTL_FILE="/etc/sysctl.d/99-maharnet.conf"
if [ -f "$SYSCTL_FILE" ]; then
    echo " -> Removing $SYSCTL_FILE..."
    rm "$SYSCTL_FILE"
else
    echo " -> $SYSCTL_FILE not found."
fi

# 2. Clean RC.Local
RC_FILE="/etc/rc.local"
if [ -f "$RC_FILE" ]; then
    echo " -> Cleaning $RC_FILE..."
    # We carefully remove ONLY our lines
    sed -i '/TCPMSS/d' "$RC_FILE"
    sed -i '/power_save/d' "$RC_FILE"
    
    # If file is now empty (or just header), we could remove it, but safer to leave it if we created it?
    # Actually, if we created it, it might just have shebang.
    if [ $(wc -l < "$RC_FILE") -le 2 ]; then
        echo "    (File matches default/empty state, deleting...)"
        rm "$RC_FILE"
    fi
else
    echo " -> $RC_FILE not found."
fi

echo "✅ Persistence Removed."
