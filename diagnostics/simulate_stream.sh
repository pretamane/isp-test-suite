#!/bin/bash
set -e

# Target: Google's Generative AI API endpoint domain (or close proxy)
TARGET="generativelanguage.googleapis.com"
SIZE_MB=20
# Limit rate to 50k (approx 400kbps) to mimic a slow token stream
RATE_LIMIT="50k"

echo "🐢 Starting Streaming Simulation..."
echo "========================================"
echo "Target: $TARGET"
echo "Simulating: Slow, bursty stream (Rate Limit: $RATE_LIMIT)"
echo "----------------------------------------"

# 1. Start tcpdump in background to capture the stall
PCAP_FILE="/tmp/stream_stall.pcap"
echo "🔍 Starting packet capture -> $PCAP_FILE"
# Capture only headers to save space, but enough to see TCP flags (SYN/ACK/RST)
# We need sudo for tcpdump inside namespace usually, but this script is aimed to run inside namespace
tcpdump -i any -s 96 -w "$PCAP_FILE" host $TARGET &
PID_DUMP=$!

# Give tcpdump a moment
sleep 2

# 2. Run the slow download
echo "⬇️  Downloading ${SIZE_MB}MB test file from speedtest.tele2.net (proxied as simulation)"
echo "    (Note: Using speedtest.tele2.net because we can't easily curl a 50MB stream from Gemini without a key/prompt)"
echo "    (The network mechanics - TCP stream - are the same)"

# We use a reliable large file source
URL="http://speedtest.tele2.net/${SIZE_MB}MB.zip"

START=$(date +%s)
# --limit-rate simulates the AI thinking/streaming time
# --max-time 120 gives it 2 minutes to fail
if curl --limit-rate "$RATE_LIMIT" --max-time 120 -o /dev/null -w "%{http_code}" "$URL"; then
    echo ""
    echo "✅ Stream completed successfully without hanging."
else
    echo ""
    echo "❌ Stream FAILED or TIMED OUT (Potential Stall Reproduced)"
fi
END=$(date +%s)
DURATION=$((END - START))

echo "----------------------------------------"
echo "⏱️  Duration: ${DURATION}s"

# 3. Stop Capture
kill "$PID_DUMP" 2>/dev/null || true
echo "💾 Capture saved. Analyze with: tcpdump -r $PCAP_FILE -n -v"
