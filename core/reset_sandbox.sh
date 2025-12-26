#!/bin/bash
set -e

# Configuration
NS="internet_box"
PHY="phy0" # This is the usual name, but we will auto-detect
WIFI_IF="wlp1s0"
VETH_HOST="veth-host"

# Ensure Root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "🧹 Starting Network Cleanup..."

# 1. Identify PHY inside Namespace (if it exists)
if ip netns list | grep -q "$NS"; then
    echo "🔍 checking namespace '$NS'..."
    PHY_INSIDE=$(ip netns exec "$NS" iw list 2>/dev/null | grep "Wiphy" | awk '{print $2}' | head -n 1)
    
    if [ -n "$PHY_INSIDE" ]; then
        echo "📡 Found '$PHY_INSIDE' in namespace. Returning to host..."
        # Set down inside
        ip netns exec "$NS" ip link set wlan0 down 2>/dev/null || true
        # Move back to PID 1 (Host namespace)
        ip netns exec "$NS" iw phy "$PHY_INSIDE" set netns 1
        echo "✅ WiFi adapter returned to Host."
    else
        echo "⚠️  No WiFi adapter found inside namespace (or name changed)."
        # Check host
        if iw list | grep -q "Wiphy"; then
            echo "   (It seems the adapter is already on the host.)"
        fi
    fi
    
    # 2. Cleanup Namespace & Veth
    echo "🗑 Deleting namespace '$NS'..."
    ip netns delete "$NS" 2>/dev/null || echo "   (Namespace already gone)"
else
    echo "✅ Namespace '$NS' not found. Nothing to clean there."
fi

# 3. Cleanup Host VETH
if ip link show "$VETH_HOST" &>/dev/null; then
    echo "🔗 Removing VETH pair..."
    ip link delete "$VETH_HOST"
fi

# 4. Restore Host WiFi State
echo "🔄 Restoring Host WiFi Service..."
rfkill unblock wifi
# Ensure interface is up (NetworkManager usually grabs it automatically)
ip link set "$WIFI_IF" up 2>/dev/null || echo "   ($WIFI_IF might be renamed or busy)"

# Trigger NetworkManager scan/connect
if command -v nmcli &>/dev/null; then
    echo "📶 Triggering NetworkManager..."
    nmcli device set "$WIFI_IF" managed yes 2>/dev/null || true
    nmcli radio wifi on
fi

echo "🎉 Reset Complete. Your system is back to default."

# 5. Re-Apply Host Optimizations (Critical for Stability)
echo "🛡️  Re-Applying MaHarNet 5G Optimizations..."
# We assume the script is in the same directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -x "$DIR/optimize_host_network.sh" ]; then
    echo "    Waiting for $WIFI_IF to initialize..."
    for i in {1..10}; do
        if ip link show "$WIFI_IF" &>/dev/null; then
             # Tiny sleep to let udev settle
             sleep 2
             "$DIR/optimize_host_network.sh" "$WIFI_IF"
             break
        fi
        sleep 1
    done
else
    echo "⚠️  Optimization script not found. You may need to run it manually."
fi
