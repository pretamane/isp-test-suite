#!/bin/bash
# debug_5g.sh - Granular analysis of 5G connection failure

SSID="MaHarNet5G"
# Assuming password same as 2G for now, or use saved profile "ContaboLab"
PROFILE="ContaboLab"

echo "🔍 Starting Deep Debug for $SSID..."

# 1. Stop Service
sudo systemctl stop wifibox

# 2. Manual Start with Signal Check
sudo wifibox start --profile $PROFILE &
PID=$!

echo "⏳ Waiting 15s for Sandbox Init..."
sleep 15

# 3. Dynamic Interface Detection
echo "--- 🔍 Detecting Interface ---"
IFACE=$(sudo ip netns exec internet_box ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -n 1)
echo "    Found Interface: $IFACE"

# 4. Insight: Signal Strength
echo "--- 📶 Signal Strength Inside Box ---"
sudo ip netns exec internet_box iw dev $IFACE link

# 5. Insight: DHCP Logs
echo "--- 🌊 DHCP Status ---"
sudo ip netns exec internet_box ip addr show $IFACE
# Check if dhclient is running
sudo ip netns pids internet_box | xargs -r ps -fp | grep dhclient

# 6. Insight: Manual MTU Sweep (if IP exists)
IP=$(sudo ip netns exec internet_box ip -4 addr show $IFACE | grep inet | awk '{print $2}')
if [ -n "$IP" ]; then
    echo "✅ IP Acquired: $IP. Starting MTU Sweep..."
    for mtu in 1500 1480 1440 1400 1360 1300 1280; do
        payload=$((mtu - 28))
        if sudo ip netns exec internet_box ping -c 1 -M do -s $payload -W 1 8.8.8.8 >/dev/null 2>&1; then
            echo "   ✅ MTU $mtu: PASS"
        else
            echo "   ❌ MTU $mtu: FAIL"
        fi
    done
else
    echo "❌ No IP Address. Checking WPA Status..."
    sudo ip netns exec internet_box wpa_cli -i $IFACE status
fi

# Cleanup if failed
# sudo wifibox stop
