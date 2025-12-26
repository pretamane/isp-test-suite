#!/bin/bash
set -e

# Configuration
NS="internet_box"
WIFI_IF="wlp1s0"
SSID="MaHarNet5G"
PSK="#ThawZin2k77!"
VETH_HOST="veth-host"
VETH_BOX="veth-box"
HOST_IP="192.168.99.1/24"
BOX_IP="192.168.99.2/24"

# Auto-detect PHY if not set
if [ -z "$PHY" ] || [ "$PHY" == "phy0" ]; then
    PHY=$(iw dev | grep -B 2 "$WIFI_IF" | grep "phy#" | awk '{print $1}' | tr -d '#')
    # fallback
    if [ -z "$PHY" ]; then PHY="phy0"; fi
fi

# Ensure host dummy file exists for bind mount
touch /etc/wpa_sup_custom.conf 2>/dev/null || true

echo "   [Debug] Using PHY: $PHY"

# 3. Move WiFi Adapter
# Check if PHY is already in namespace (Check for string Wiphy)
if ip netns exec "$NS" iw list | grep -q "Wiphy"; then
    echo "✅ WiFi adapter is already inside '$NS'."
else
    echo "📡 Moving '$PHY' to '$NS'..."
    
    # Ensure it's down on the host
    ip link set "$WIFI_IF" down || true
    
    # Ensure not blocked
    rfkill unblock wifi
    
    # Move it
    if iw phy "$PHY" set netns name "$NS"; then
        echo "✅ Moved $PHY to $NS"
    else
        echo "❌ Failed to move $PHY. It might be in use or missing."
        # Try to find if it's just named differently
        iw list
        exit 1
    fi
    sleep 1
fi

# Create Interface if missing
echo "🛠 Checking for WiFi interface..."
# Debug: List PHYs inside
echo "   [Debug] PHYs inside $NS:"
ip netns exec "$NS" iw list | grep Wiphy || true

# Find the PHY name inside the namespace
PHY_INSIDE=$(ip netns exec "$NS" iw list | grep "Wiphy" | awk '{print $2}' | head -n 1)

if [ -z "$PHY_INSIDE" ]; then
    echo "❌ No Wiphy found inside namespace! The move might have failed."
    exit 1
fi

echo "   Found PHY: $PHY_INSIDE"

# Check for existing interface on this PHY
WIFI_IF=$(ip netns exec "$NS" iw dev | grep Interface | awk '{print $2}' | head -n 1)

if [ -z "$WIFI_IF" ]; then
    echo "⚠️ No interface found. Creating 'wlan0' on $PHY_INSIDE..."
    ip netns exec "$NS" iw phy "$PHY_INSIDE" interface add wlan0 type managed
    WIFI_IF="wlan0"
fi

echo "✅ Using Interface: $WIFI_IF"
# Try unblock inside
ip netns exec "$NS" rfkill unblock wifi || true
ip netns exec "$NS" ip link set "$WIFI_IF" up

# 4. Connect to WiFi (Inside Namespace)
echo "🔐 Configuring WiFi connection inside '$NS'..."

mkdir -p /etc/netns/$NS

# Create wpa_supplicant config
# We use a distinct name to avoid ip-netns binding issues if /etc/wpa_supplicant.conf doesn't exist on host
CONF_FILE="/etc/netns/$NS/wpa_sup_custom.conf"

cat > "$CONF_FILE" <<EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1
network={
    ssid="$SSID"
    psk="$PSK"
}
EOF

# Kill existing wpa_supplicant in namespace if any
ip netns exec "$NS" pkill wpa_supplicant || true
sleep 1

# Start wpa_supplicant
echo "⚡ Starting wpa_supplicant..."
# Running in background
ip netns exec "$NS" wpa_supplicant -B -i "$WIFI_IF" -c "$CONF_FILE"

echo "⏳ Waiting for association (10s)..."
sleep 10

# Start DHCP
# We ignore errors here in case it's already running or slow, script should continue to optimization
echo "🌊 Requesting IP via DHCP..."
ip netns exec "$NS" pkill dhclient || true
ip netns exec "$NS" dhclient -v "$WIFI_IF" || true

# 4.5 Auto-Optimize MTU
optimize_mtu() {
    echo "📏 Optimizing MTU for ISP compatibility..."
    local check_ip="8.8.8.8"
    local mtu_candidates=(1400 1360 1320 1280)
    
    # Try finding the largest working MTU
    for mtu in "${mtu_candidates[@]}"; do
        # Ping payload = MTU - 28 (IP Header 20 + ICMP Header 8)
        local payload=$((mtu - 28))
        if ip netns exec "$NS" ping -c 1 -M do -s "$payload" -W 1 "$check_ip" &>/dev/null; then
            echo "✅  MTU $mtu is SAFE."
            echo "⚙️  Setting MTU to $mtu..."
            ip netns exec "$NS" ip link set "$WIFI_IF" mtu "$mtu"
            return 0
        else
            echo "❌  MTU $mtu too large (fragmented/dropped)."
        fi
    done
    
    echo "⚠️  Could not find optimal MTU in common range. Setting conservative default: 1400."
    ip netns exec "$NS" ip link set "$WIFI_IF" mtu 1400
}

optimize_mtu

# 5. Verification
echo "🔍 Verifying Connectivity..."
IP_ADDR=$(ip netns exec "$NS" ip -4 addr show "$WIFI_IF" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -n "$IP_ADDR" ]; then
    echo "✅ Connected! IP: $IP_ADDR"
    echo "pinging 1.1.1.1..."
    ip netns exec "$NS" ping -c 2 1.1.1.1
else
    echo "❌ Failed to get IP address."
    exit 1
fi

echo "🎉 Sandbox Setup Complete."
echo "   - Host IP: 192.168.99.1"
echo "   - Sandbox IP: 192.168.99.2"
echo "   - Run commands in sandbox: ip netns exec $NS <command>"
