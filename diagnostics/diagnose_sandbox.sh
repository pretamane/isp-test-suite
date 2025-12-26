#!/bin/bash
# diagnose_sandbox.sh - Run INSIDE the namespace (internet_box)

TARGET="generativelanguage.googleapis.com"
INTERFACE="wlp1s0"

echo "============================================"
echo "🕵️  Deep Sandbox Diagnostic: AntiGravity API"
echo "============================================"

# 1. Interface Check
echo -e "\n[1] Checking WiFi Interface ($INTERFACE)..."
IP_ADDR=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -z "$IP_ADDR" ]; then
    echo "❌ ERROR: No IP address on $INTERFACE"
    exit 1
else
    echo "✅ IP Assigned: $IP_ADDR"
    iw dev $INTERFACE link | grep -E "SSID|signal|tx bitrate"
fi

# 2. Routing Check
echo -e "\n[2] Checking Route to Google ($TARGET)..."
ROUTE=$(ip route get 8.8.8.8)
VIA_IF=$(echo "$ROUTE" | grep -o "dev \w*" | awk '{print $2}')
if [ "$VIA_IF" != "$INTERFACE" ]; then
    echo "❌ ERROR: Traffic routing through $VIA_IF, NOT $INTERFACE!"
    exit 1
else
    echo "✅ Route OK: Traffic flows through $INTERFACE"
fi

# 3. DNS Resolution
echo -e "\n[3] Checking DNS Resolution..."
if host $TARGET > /dev/null; then
    API_IP=$(host $TARGET | grep -m1 "has address" | awk '{print $4}')
    echo "✅ Resolved: $TARGET -> $API_IP"
else
    echo "❌ ERROR: Failed to resolve $TARGET"
    echo "    Testing fallback DNS (8.8.8.8)..."
    ping -c 1 8.8.8.8 >/dev/null && echo "    ✅ Google DNS is reachable (IP)" || echo "    ❌ Google DNS is unreachable (IP)"
fi

# 4. Traceroute (The Ultimate Truth)
echo -e "\n[4] Tracing Path to Google API..."
if [ ! -z "$API_IP" ]; then
    # Force IPv4 tracepath
    tracepath -n $API_IP | head -n 3
    echo "    (Hop 1 should be the MaHarNet Gateway, e.g., 192.168.1.1)"
else
    echo "⚠️  Skipping Tracepath (No IP resolved)"
fi

# 5. Application Layer Test (SSL Handshake / API Call)
echo -e "\n[5] Testing API Connectivity (Curl)..."
# Force IPv4 (-4)
RESPONSE=$(curl -4 -v -s -o /dev/null -w "%{http_code}" --connect-timeout 8 "https://$TARGET/v1beta/models/gemini-pro?key=TEST_CHECK")

if [[ "$RESPONSE" =~ ^4 ]]; then
    echo "✅ SUCCESS: API reachable! (Received HTTP $RESPONSE - Expected for invalid key)"
elif [[ "$RESPONSE" == "200" ]]; then
     echo "✅ SUCCESS: API reachable! (Received HTTP 200)"
else
    echo "❌ FAILURE: API Unreachable. HTTP Code: $RESPONSE"
    echo "    Possible issues: MTU, Firewall, or DPI blocking."
fi

echo "============================================"
