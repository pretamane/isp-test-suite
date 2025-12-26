#!/bin/bash
# simulate_stall.sh - Simulates a heavy AntiGravity API request
# Runs inside the sandbox to test for MTU/Fragmentation stalls.

TARGET="https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=TEST_KEY"

# Create a large dummy payload (approx 5KB) to force packet fragmentation
echo "📦 Generating 5KB Dummy Payload..."
PAYLOAD=$(printf '{"contents":[{"parts":[{"text":"%*s"}]}]}' 5000 | tr ' ' 'a')

echo "🚀 Sending Heavy Request to Gemini API..."
echo "    - Timeout: 15s"
echo "    - MTU: $(cat /sys/class/net/wlp1s0/mtu)"
echo "    - Payload Size: ~5KB"

# Time the request
START=$(date +%s%N)
response=$(curl -v -X POST "$TARGET" \
     -H "Content-Type: application/json" \
     -d "$PAYLOAD" \
     --connect-timeout 10 \
     --max-time 15 2>&1)
EXIT_CODE=$?
END=$(date +%s%N)

DURATION=$(( ($END - $START) / 1000000 ))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ STALL DETECTED! (Curl Exit Code: $EXIT_CODE)"
    echo "    Duration: ${DURATION}ms"
    echo "    Error: $response" | tail -n 5
else
    echo "✅ SUCCESS: Payload Delivered in ${DURATION}ms"
    # Check for HTTP 400 (Expected) vs Connection Reset
    if echo "$response" | grep -q "400 Bad Request"; then
        echo "    Status: API Rejected Key (Good - Connection is Stable)"
    else
        echo "    Status: Unexpected Response (See detailed logs)"
    fi
fi
