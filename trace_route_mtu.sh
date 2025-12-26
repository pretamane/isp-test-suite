#!/bin/bash
set -e

TARGET="generativelanguage.googleapis.com"

echo "🔎 Tracing Path MTU to $TARGET..."
echo "========================================"

# Check for tracepath
if ! command -v tracepath &>/dev/null; then
    echo "❌ tracepath not found. Please install iputils-tracepath."
    # Fallback to simple ping sweep
    echo "⚠️  Falling back to manual ping sweep..."
    
    # Standard MTU sizes to try
    SIZES=(1500 1492 1480 1472 1460 1452 1440 1420 1400 1380 1360 1300)
    
    for mtu in "${SIZES[@]}"; do
        payload=$((mtu - 28))
        echo -n "   Testing MTU $mtu (Payload $payload)... "
        if ping -c 1 -M do -s "$payload" -W 1 "$TARGET" &>/dev/null; then
            echo "✅ YES"
            echo "🎉 Max viable MTU found: $mtu"
            exit 0
        else
            echo "❌ NO"
        fi
    done
    echo "⚠️  Could not determine exact MTU. Try setting conservative 1300."
    exit 1
fi

# Run tracepath
tracepath -n "$TARGET"
