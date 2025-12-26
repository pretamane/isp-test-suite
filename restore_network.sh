#!/bin/bash
# restore_network.sh
# Restores network configuration to default state (Undo Split Routing)

WIFI_CONN="MaHarNet5G"

# Dynamic Wired Detection
WIRED_IF=$(nmcli -t -f DEVICE,TYPE device | grep ethernet | head -n1 | cut -d: -f1)
if [ -n "$WIRED_IF" ]; then
    WIRED_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$WIRED_IF" | cut -d: -f1)
fi
echo "    Detected Wired Connection: ${WIRED_CONN:-None}"

# Clean both potential IDs
GIDS=("1001" "1002" "3000")
MARKS=("0x1001" "0x1002" "0x3000")
NS="internet_box"

echo ">>> Restoring Network Configuration..."

# 0. WiFiBox Cleanup (Namespace & PHY)
if ip netns list | grep -q "$NS"; then
    echo " -> Detect WiFiBox Namespace. Cleaning up..."
    PHY_INSIDE=$(ip netns exec "$NS" iw list 2>/dev/null | grep "Wiphy" | awk '{print $2}' | head -n 1)
    if [ -n "$PHY_INSIDE" ]; then
        echo "    Moving '$PHY_INSIDE' back to host..."
        ip netns exec "$NS" ip link set wlan0 down 2>/dev/null
        ip netns exec "$NS" iw phy "$PHY_INSIDE" set netns 1
    fi
    ip netns delete "$NS"
    ip link delete veth-host 2>/dev/null
fi

# 1. Remove IPTables Rule
echo " -> Removing IPTables Rule..."
for GID in "${GIDS[@]}"; do
    # Remove all possible marks for this GID
    for MARK in "${MARKS[@]}"; do
         while iptables -t mangle -D OUTPUT -m owner --gid-owner $GID -j MARK --set-mark $MARK 2>/dev/null; do :; done
    done
done

# 2. Remove IP Rule
echo " -> Removing Policy Routing Rule..."
for MARK in "${MARKS[@]}"; do
    while ip rule del fwmark $MARK table wired 2>/dev/null; do :; done
done

# 3. Flush Wired Table
echo " -> Flushing Wired Routing Table..."
ip route flush table wired

# 4. Reset Connection Metrics
# Default Linux/NM behavior: Wired (100) > WiFi (600)
echo " -> Resetting Connection Metrics (Reverting to system default)..."
nmcli connection modify "$WIFI_CONN" ipv4.route-metric 600
nmcli connection modify "$WIRED_CONN" ipv4.route-metric 100

# Apply changes
echo " -> Reactivating Connections..."
nmcli connection up "$WIFI_CONN"
nmcli connection up "$WIRED_CONN" &>/dev/null

# 5. Remove Anti-Stall Fixes (MSS Clamping)
echo " -> Removing MSS Clamping Rules..."
if command -v iptables &>/dev/null; then
    while iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do :; done
fi

# 6. Reset Kernel Tuning (Safe Defaults)
echo " -> Resetting Kernel TCP Parameters..."
sysctl -w net.ipv4.tcp_mtu_probing=0 &>/dev/null
# We don't necessarily need to revert buffers/BBR as they are generally good, 
# but for strict "restore default":
sysctl -w net.ipv4.tcp_congestion_control=cubic &>/dev/null

echo ">>> Restore Complete!"
echo "System returned to default network behavior (Wired preferred)."
