#!/bin/bash
TARGET_IP="142.251.222.74"
GATEWAY="192.168.98.2"

echo "🚀 Setting up AntiGravity Route..."
# Add temporary route
sudo ip route add $TARGET_IP/32 via $GATEWAY dev veth-wifi-host

echo "📡 Testing Connectivity to Google Generative Language API..."
# Use curl with forced IP resolution to ensure it hits the routed path
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --resolve generativelanguage.googleapis.com:443:$TARGET_IP --connect-timeout 5 "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro?key=TEST_KEY")

echo "🔍 HTTP Status Code: $HTTP_CODE"

# Cleanup
echo "🧹 Cleaning up..."
sudo ip route del $TARGET_IP/32 via $GATEWAY dev veth-wifi-host

if [[ "$HTTP_CODE" =~ ^4 ]]; then
    echo "✅ SUCCESS: Reached API (Got expected 4xx error for invalid key)"
    exit 0
elif [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ SUCCESS: Reached API (200 OK)"
    exit 0
else
    echo "❌ FAILURE: Initial connection failed or timed out (Code: $HTTP_CODE)"
    exit 1
fi
