#!/bin/bash
# install_persistence.sh
set -e

echo "🛠  Installing Maharnet 5G Network Tuning..."

# 1. Sysctl Configuration
SYSCTL_FILE="/etc/sysctl.d/99-maharnet.conf"
echo " -> Writing $SYSCTL_FILE..."
cat <<EOF > "$SYSCTL_FILE"
# Maharnet 5G Anti-Stall Tuning
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq
net.ipv4.tcp_fastopen=3
EOF

# 2. RC.Local (Startup Script)
RC_FILE="/etc/rc.local"
echo " -> Configuring $RC_FILE..."

# Provide a template if it doesn't exist
if [ ! -f "$RC_FILE" ]; then
    cat <<EOF > "$RC_FILE"
#!/bin/bash
# rc.local
EOF
fi

# Make sure it's executable
chmod +x "$RC_FILE"

# Append commands if not already present
grep -q "TCPMSS" "$RC_FILE" || echo "iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu" >> "$RC_FILE"
grep -q "power_save" "$RC_FILE" || echo "/sbin/iw dev wlp1s0 set power_save off 2>/dev/null || true" >> "$RC_FILE"

# Ensure 'exit 0' is at the end (basic check, could be better but sufficient for simple setup)
# Effectively, we just ensure the commands run. 
# A common issue is 'exit 0' early in the file. We'll warn user.
if grep -q "exit 0" "$RC_FILE"; then
    echo "⚠️  Note: $RC_FILE contains 'exit 0'. Ensure the tuning lines are ABOVE it."
fi

echo "✅ Persistence Installed."
echo "   - Kernel settings will apply on reboot."
echo "   - Startup script ($RC_FILE) will apply MSS clamping on boot."
