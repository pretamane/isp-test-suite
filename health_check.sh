#!/bin/bash
set -e

# Configuration
TARGET_HOST="8.8.8.8"
DNS_HOST="1.1.1.1"
UPLOAD_ENDPOINT="http://speedtest.tele2.net/upload.php" # Generic upload test
DOWNLOAD_ENDPOINT="http://speedtest.tele2.net/10MB.zip"
COUNT=10

echo "🏥 Starting Maharnet 5G Health Check..."
echo "========================================"

# 1. Basic Connectivity & Latency
echo "📡 1. Checking Connectivity & Latency (Ping $TARGET_HOST)..."
ping -c $COUNT -q $TARGET_HOST > /tmp/ping_stats.txt
LOSS=$(grep -oP '\d+(?=% packet loss)' /tmp/ping_stats.txt)
AVG_RTT=$(grep -oP 'min/avg/max/mdev = \K[0-9.]+\/[0-9.]+' /tmp/ping_stats.txt | cut -d/ -f2)
JITTER=$(grep -oP 'min/avg/max/mdev = \K[0-9.]+\/[0-9.]+\/[0-9.]+\/[0-9.]+' /tmp/ping_stats.txt | cut -d/ -f4)

echo "   - Packet Loss: $LOSS%"
echo "   - Avg Latency: ${AVG_RTT}ms"
echo "   - Jitter:      ${JITTER}ms"

if [ "$LOSS" -gt 0 ]; then
    echo "⚠️  WARNING: Packet loss detected!"
else
    echo "✅ Connectivity looks stable."
fi

echo "----------------------------------------"

# 2. DNS Resolution Speed
echo "🌍 2. DNS Resolution Speed ($DNS_HOST)..."
DNS_START=$(date +%s%N)
nslookup google.com $DNS_HOST > /dev/null
DNS_END=$(date +%s%N)
DNS_TIME=$(( (DNS_END - DNS_START) / 1000000 ))
echo "   - Resolution Time: ${DNS_TIME}ms"
echo "----------------------------------------"

# 3. Bandwidth (Approximate)
echo "🚀 3. Bandwidth Test..."

# Download
echo "   ⬇️  Testing Download Speed (10MB)..."
TIME_DL=$(curl -w "%{time_total}\n" -o /dev/null -s $DOWNLOAD_ENDPOINT)
# Speed in Mbps = (10MB * 8 bits) / time
DL_SPEED=$(echo "10 * 8 / $TIME_DL" | bc -l)
printf "   - Download Speed: %.2f Mbps (Time: ${TIME_DL}s)\n" "$DL_SPEED"

# Upload
echo "   ⬆️  Testing Upload Speed (100KB)..."
# Create 100KB Dummy File
dd if=/dev/zero of=/tmp/upload.test bs=100K count=1 status=none
TIME_UL=$(curl --max-time 20 -w "%{time_total}\n" -o /dev/null -s -F "file=@/tmp/upload.test" $UPLOAD_ENDPOINT || echo "ERR")

if [ "$TIME_UL" == "ERR" ]; then
    echo "   - Upload Speed:   FAILED (Timeout or Error)"
else
    # Speed in Mbps = (100KB * 8 bits) / time
    # 100KB = 0.1 MB
    UL_SPEED=$(echo "0.1 * 8 / $TIME_UL" | bc -l)
    printf "   - Upload Speed:   %.2f Mbps (Time: ${TIME_UL}s)\n" "$UL_SPEED"
fi

rm -f /tmp/upload.test
echo "----------------------------------------"

# 4. Stress / Stability
echo "🔥 4. Connection Stability (Concurrent Connections)..."
echo "   Running 5 parallel requests to google.com..."
(
    curl -s -o /dev/null https://www.google.com &
    curl -s -o /dev/null https://www.google.com &
    curl -s -o /dev/null https://www.google.com &
    curl -s -o /dev/null https://www.google.com &
    curl -s -o /dev/null https://www.google.com &
    wait
) && echo "✅ All parallel requests completed successfully." || echo "❌ Parallel requests failed."

echo "========================================"
echo "🎉 Health Check Complete."
