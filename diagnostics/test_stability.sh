#!/bin/bash
set -e

TARGET_URL="https://generativelanguage.googleapis.com"
LARGE_FILE_URL="http://speedtest.tele2.net/100MB.zip" # Standard speedtest file
COUNT=20

echo "🤖 Starting Stability Stress Test..."
echo "Configured MTU: $(ip link show wlp1s0 | grep -o 'mtu [0-9]*')"
echo "----------------------------------------"

# 1. SSL/TLS Handshake Stability (Mimics AI API calls)
echo "🔄 Test 1: Repeated SSL Handshakes to Google AI ($COUNT requests)..."
SUCCESS=0
for i in $(seq 1 $COUNT); do
    if curl -s -I "$TARGET_URL" > /dev/null; then
        echo -n "."
        SUCCESS=$((SUCCESS+1))
    else
        echo -n "X"
    fi
    # Sleep slightly to mimic chatter
    sleep 0.2
done
echo ""
if [ "$SUCCESS" -eq "$COUNT" ]; then
    echo "✅ SSL Handshake: 100% Success ($SUCCESS/$COUNT)"
else
    echo "❌ SSL Handshake: Failed ($((COUNT-SUCCESS)) errors)"
fi
echo "----------------------------------------"

# 2. Latency Under Load
echo "⏱️  Test 2: Latency check (Google DNS)..."
ping -c 5 -q 8.8.8.8
echo "----------------------------------------"

# 3. Large Data Transfer (Mimics Model Downloads / Context Uploads)
echo "📦 Test 3: Large File Download (MTU Stress Test)..."
echo "   Downloading 100MB test file (timeout 60s)..."
# We limit to 60s to avoid wasting time if it's slow, but we want to see it sustain
if curl -o /dev/null --max-time 60 --progress-bar "$LARGE_FILE_URL"; then
    echo "✅ Large Download: SUCCESS (Sustained connection held)"
else
    RET=$?
    if [ $RET -eq 28 ]; then
         echo "⚠️  Large Download: Timed out (Slow speed, but connection didn't drop)"
    else
         echo "❌ Large Download: FAILED (Error code: $RET)"
    fi
fi
echo "----------------------------------------"

echo "🎉 Test Complete."
