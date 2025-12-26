#!/bin/bash
set -e

# Ensure Root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "🛠  Starting Network Optimization & Tuning..."
echo "========================================"

# 1. Wireless Driver Optimization
WIFI_IF=$(ip addr | grep -B 2 "wlp" | head -n 1 | awk -F: '{print $2}' | tr -d ' ')
# Fallback if detection fails (common name)
if [ -z "$WIFI_IF" ]; then WIFI_IF="wlp1s0"; fi

echo "📡 1. Tuning Wireless Driver ($WIFI_IF)..."
if iw dev "$WIFI_IF" info &>/dev/null; then
    # Disable Power Save
    iw dev "$WIFI_IF" set power_save off
    echo "   - Power Save: OFF"
    
    # Attempt to set TX Queue Len (often helps with bufferbloat)
    ip link set dev "$WIFI_IF" qlen 1000
    echo "   - TX Queue Len: 1000"
else
    echo "⚠️  Interface $WIFI_IF not found or not a wifi device. Skipping driver tuning."
fi
echo "----------------------------------------"

# 2. Kernel TCP Optimizations (Sysctl)
echo "🧠 2. Applying Kernel TCP Optimizations..."

# Backup current settings
sysctl -a | grep -E "net.core.rmem_max|net.core.wmem_max|net.ipv4.tcp_rmem|net.ipv4.tcp_wmem|net.ipv4.tcp_congestion_control" > /tmp/sysctl_backup.conf
echo "   (Backup saved to /tmp/sysctl_backup.conf)"

# Increase Buffer Sizes (for high BDP paths like 5G)
sysctl -w net.core.rmem_max=16777216 > /dev/null
sysctl -w net.core.wmem_max=16777216 > /dev/null
sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216" > /dev/null
sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216" > /dev/null
echo "   - Increased TCP Read/Write Buffers"

# Enable TCP BBR (Bottleneck Bandwidth and Round-trip propagation time)
# BBR is generally better for variable cellular networks
if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control; then
    sysctl -w net.core.default_qdisc=fq > /dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null
    echo "   - Congestion Control: BBR (Enabled)"
else
    echo "   - Congestion Control: Cubic (BBR not available, module maybe missing)"
fi

# TCP Fast Open & Keepalive
sysctl -w net.ipv4.tcp_fastopen=3 > /dev/null
sysctl -w net.ipv4.tcp_keepalive_time=60 > /dev/null
sysctl -w net.ipv4.tcp_keepalive_intvl=10 > /dev/null
sysctl -w net.ipv4.tcp_keepalive_probes=6 > /dev/null
echo "   - Enabled TCP Fast Open & Optimized Keepalive"

# --- NEW: Fix for "Stalling" / "Blackhole" routers ---
echo "🛡️  3. Applying MTU/MSS Fixes (Anti-Stall)..."

# 1. Enable TCP MTU Probing (Kernel will auto-detect dropped large packets and reduce sizing)
# 0=disabled, 1=on (when detecting blackhole), 2=always on
sysctl -w net.ipv4.tcp_mtu_probing=1 > /dev/null
echo "   - TCP MTU Probing: Enabled (Mode 1)"

# 2. MSS Clamping (Firewall level)
# This forces the MSS (Max Segment Size) to match the negotiated MTU (PMTU), preventing sending packets purely based on local MTU
if command -v iptables &>/dev/null; then
    # Check if rule exists
    if iptables -t mangle -C POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
        echo "   - MSS Clamping: already active"
    else
        iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
        echo "   - MSS Clamping: Enabled (iptables)"
    fi
else
    echo "⚠️  iptables not found. MSS clamping skipped (Try installing iptables)."
fi

echo "----------------------------------------"
echo "✅ Tuning Applied. (Settings are transient and will reset on reboot)"
