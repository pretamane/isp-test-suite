#!/bin/bash
set -e

NS="internet_box"
echo "🔍 Starting Deep Layer Analysis..."

# 1. Namespace Isolation Check (The "Wall")
echo -e "\n--- 1. The Wall (Namespace Isolation) ---"
echo "Host Routing Table (Main):"
ip route | head -n 3
echo "..."
echo "Sandbox Routing Table ($NS):"
sudo ip netns exec $NS ip route

echo -e "\n👉 Explanation: note that the Sandbox has NO idea about your USB tether (192.168.x.x on host) or other interfaces."

# 2. DNS Leak Test
echo -e "\n--- 2. DNS Leak Test ---"
echo "Querying Google via Sandbox..."
sudo ip netns exec $NS curl -s https://dns.google/resolve?name=myip.opendns.com&type=TXT | grep "answer" || echo "DNS Query Failed"
echo -e "\n👉 Explanation: If this works, your DNS queries are successfully tunneling through the WiFi."

# 3. Connection Tracking (The "Pipe")
echo -e "\n--- 3. Active Connections ---"
echo "Sockets inside the box:"
sudo ip netns exec $NS ss -tun dst :443
echo -e "\n👉 Explanation: These are the actual TCP connections your AI/Scripts are making."

# 4. Packet Capture (The "Proof")
echo -e "\n--- 4. Live Packet Capture (3 seconds) ---"
echo "Listening on wlan0 inside sandbox... (Generate some traffic now!)"
# Start a ping in background to generate traffic
sudo ip netns exec $NS ping -c 4 8.8.8.8 > /dev/null &
# Capture headers
sudo ip netns exec $NS timeout 3 tcpdump -n -i any icmp or port 443 2>/dev/null | head -n 10
echo -e "\n👉 Explanation: You should see packets flowing on 'wlan0' (or 'any' inside box). You will NOT see Host traffic here."

echo -e "\n✅ Deep Verification Complete."
