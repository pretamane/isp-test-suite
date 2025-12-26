#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os
import time
import json
import shutil
import re

# --- Configuration ---
PROFILE_DIR = "/etc/wifibox"
PROFILE_FILE = os.path.join(PROFILE_DIR, "profiles.json")
NS = "internet_box"
VETH_HOST = "veth-wifi-host"
VETH_BOX = "veth-wifi-box"
HOST_IP = "192.168.98.1/24"
BOX_IP = "192.168.98.2/24"
# ---------------------

def run_command(cmd, check=True, capture_output=True):
    """Run a shell command."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            check=check,
            stdout=subprocess.PIPE if capture_output else None,
            stderr=subprocess.PIPE if capture_output else None,
            text=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        if not check:
            return None
        print(f"❌ Error running command: {cmd}")
        print(f"   Stderr: {e.stderr.strip() if e.stderr else 'None'}")
        sys.exit(1)

def ensure_root():
    if os.geteuid() != 0:
        print("❌ This tool requires root privileges. Please run with sudo.")
        sys.exit(1)

# --- Profile Management ---
def load_profiles():
    # Check multiple locations
    locations = [
        PROFILE_FILE,
        "/etc/wifibox/profiles.json",
        "/root/.config/wifibox/profiles.json"
    ]
    
    for loc in locations:
        if os.path.exists(loc):
            try:
                with open(loc, 'r') as f:
                    return json.load(f)
            except json.JSONDecodeError:
                continue
    return {}

def save_profiles(profiles):
    if not os.path.exists(PROFILE_DIR):
        os.makedirs(PROFILE_DIR, mode=0o700)
    with open(PROFILE_FILE, 'w') as f:
        json.dump(profiles, f, indent=4)
        
def cmd_save(args):
    """Save a WiFi profile."""
    profiles = load_profiles()
    profiles[args.name] = {
        "ssid": args.ssid,
        "password": args.password
    }
    save_profiles(profiles)
    print(f"✅ Profile '{args.name}' saved.")

def cmd_list(args):
    """List WiFi profiles."""
    profiles = load_profiles()
    if not profiles:
        print("No profiles found.")
        return
    print("Saved Profiles:")
    for name, data in profiles.items():
        print(f"  - {name} (SSID: {data['ssid']})")

# --- Core Logic ---

def find_phy_in_ns(namespace):
    """Finds the PHY name inside a namespace."""
    try:
        output = run_command(f"ip netns exec {namespace} iw list", check=False)
        if not output: return None
        match = re.search(r"Wiphy\s+(\S+)", output)
        return match.group(1) if match else None
    except:
        return None

def find_host_phy():
    """Finds the first PHY on the host."""
    try:
        output = run_command("iw list", check=False)
        if not output: return None
        match = re.search(r"Wiphy\s+(\S+)", output)
        return match.group(1) if match else None
    except:
        return None

def start_sandbox(ssid, password, no_dhcp=False, static_ip=None, gateway=None, mac_address=None):
    """Core logic to set up the sandbox."""
    print(f"🚀 Starting WiFiBox for SSID: {ssid}...", flush=True)
    print(f"    DEBUG: static_ip={static_ip}, mac={mac_address}", flush=True)

    # 1. Namespace
    if NS not in run_command("ip netns list", check=False):
        print(f"📦 Creating namespace '{NS}'...")
        run_command(f"ip netns add {NS}")
        run_command(f"ip netns exec {NS} ip link set lo up")
    else:
        print(f"✅ Namespace '{NS}' exists.")

    # 2. VETH
    if not run_command(f"ip link show {VETH_HOST}", check=False):
        print("🔗 Creating VETH pair...")
        run_command(f"ip link add {VETH_HOST} type veth peer name {VETH_BOX}")
        run_command(f"ip link set {VETH_BOX} netns {NS}")
        run_command(f"ip addr add {HOST_IP} dev {VETH_HOST}")
        run_command(f"ip link set {VETH_HOST} up")
        run_command(f"ip netns exec {NS} ip addr add {BOX_IP} dev {VETH_BOX}")
        run_command(f"ip netns exec {NS} ip link set {VETH_BOX} up")

    # 3. Move PHY
    # Check if already inside
    phy_inside = find_phy_in_ns(NS)
    if phy_inside:
        print(f"✅ PHY '{phy_inside}' is already in sandbox.")
        phy_name = phy_inside
    else:
        # Move from host
        phy_host = find_host_phy()
        if not phy_host:
            print("❌ No WiFi adapter (Wiphy) found on Host!")
            # If in monitor mode, we might want to wait, but for now exit/raise
            return False
        
        print(f"📡 Moving '{phy_host}' to '{NS}'...")
        # Try to unmanage/down on host 
        output = run_command("iw dev")
        if output:
            match = re.search(r"Interface\s+(\S+)", output)
            if match:
                iface = match.group(1)
                run_command(f"ip link set {iface} down", check=False)
        
        run_command("rfkill unblock wifi")
        run_command(f"iw phy {phy_host} set netns name {NS}")
        time.sleep(1) # Wait for move
        
        # Re-detect name inside
        phy_name = find_phy_in_ns(NS)
        if not phy_name:
             print("❌ Failed to find PHY inside namespace after move.")
             return False

    # 4. Create Interface inside
    wifi_if = run_command(f"ip netns exec {NS} iw dev", check=False)
    if "Interface" not in (wifi_if or ""):
        print(f"🛠 Creating 'wlan0' on {phy_name}...")
        run_command(f"ip netns exec {NS} iw phy {phy_name} interface add wlan0 type managed")
        real_if = "wlan0"
    else:
        match = re.search(r"Interface\s+(\S+)", wifi_if)
        real_if = match.group(1) if match else "wlan0"
    
    print(f"✅ Using Interface: {real_if}")
    
    # 5.5 MAC Spoofing (Applied on the interface)
    if mac_address:
         print(f"🎭 Applying Spoofed MAC: {mac_address}")
         run_command(f"ip netns exec {NS} ip link set {real_if} down", check=False)
         run_command(f"ip netns exec {NS} ip link set {real_if} address {mac_address}", check=False)
    
    run_command(f"ip netns exec {NS} rfkill unblock wifi", check=False)
    run_command(f"ip netns exec {NS} ip link set {real_if} up")
    
    # NEW: Disable Power Save for Stability
    print("⚡ Disabling WiFi Power Save...")
    run_command(f"ip netns exec {NS} iw dev {real_if} set power_save off", check=False)

    # 5. Connect (WPA Supplicant)
    print("🔐 Configuring WPA Supplicant...")
    run_command(f"mkdir -p /etc/netns/{NS}")
    conf_path = f"/etc/netns/{NS}/wpa_custom.conf"
    
    # Set Country Code for Regulatory Compliance
    print("🌍 Setting Regulatory Domain to 'US'...", flush=True)
    run_command(f"ip netns exec {NS} iw reg set US", check=False)
    
    # Set TxPower (Fine Tuning)
    print("💪 Setting TxPower to 20dBm...", flush=True)
    run_command(f"ip netns exec {NS} iw dev {real_if} set txpower fixed 2000", check=False)

    with open(conf_path, "w") as f:
        f.write("ctrl_interface=/var/run/wpa_supplicant\n")
        f.write("update_config=1\n")
        f.write("network={\n")
        f.write(f'    ssid="{ssid}"\n')
        f.write(f'    psk="{password}"\n')
        f.write("    scan_ssid=1\n")
        f.write("    key_mgmt=WPA-PSK\n")
        f.write("    # Mixed Mode for Maximum Compatibility\n")
        f.write("    proto=RSN WPA\n")
        f.write("    pairwise=CCMP TKIP\n")
        f.write("    group=CCMP TKIP\n")
        f.write("}\n")
    
    run_command(f"ip netns exec {NS} pkill wpa_supplicant", check=False)
    time.sleep(1)
    # Hard Reset Radio before starting WPA
    run_command(f"ip netns exec {NS} ip link set {real_if} down", check=False)
    time.sleep(1)
    run_command(f"ip netns exec {NS} ip link set {real_if} up", check=False)
    
    # Debug mode -dd for wpa_supplicant
    subprocess.Popen(f"ip netns exec {NS} wpa_supplicant -dd -B -i {real_if} -c {conf_path}", shell=True)
    
    print("⏳ Waiting for association (10s)...")
    time.sleep(10)
    


    # 7. Auto-Optimize MTU
    print("📏 Auto-Optimizing MTU...")
    mtu_list = [1400, 1360, 1320, 1280]
    best_mtu = 1360
    for mtu in mtu_list:
        payload = mtu - 28
        res = subprocess.run(
            f"ip netns exec {NS} ping -c 1 -M do -s {payload} -W 1 8.8.8.8",
            shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        if res.returncode == 0:
            best_mtu = mtu
            print(f"✅ MTU {mtu} passed.")
            break
        else:
            print(f"❌ MTU {mtu} failed.")
            
    print(f"⚙️  Setting MTU to {best_mtu}")
    run_command(f"ip netns exec {NS} ip link set {real_if} mtu {best_mtu}")
    # 7. IP Configuration
    if static_ip:
        print(f"⚙️  Setting Static IP: {static_ip}")
        # Ensure interface is UP first
        run_command(f"ip netns exec {NS} ip link set {real_if} up", check=False)
        
        # Add IP (ignore error if exists)
        res = subprocess.run(
             f"ip netns exec {NS} ip addr add {static_ip} dev {real_if}",
             shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        if res.returncode != 0:
             print(f"⚠️  Static IP warning: {res.stderr.decode().strip()}")
             
        if gateway:
             print(f"⚙️  Setting Gateway: {gateway}")
             run_command(f"ip netns exec {NS} ip route add default via {gateway}", check=False)
             
    elif no_dhcp:
        print("⏭️  Skipping DHCP as requested.")
    else:
        print("🌊 Requesting IP (DHCP)...")
        try:
           # Existing DHCP logic
           run_command(f"ip netns exec {NS} pkill dhclient", check=False)
           run_command(f"ip netns exec {NS} dhclient -v {real_if}")
        except subprocess.CalledProcessError:
             print("❌ DHCP Failed.")
             cleanup_sandbox(quiet=True) # This function is not defined in the provided code.
             return False
        
    # 8. Setup NAT (Router Mode)
    print("🌐 Enabling NAT (Router Mode)...")
    # Enable IP Forwarding
    run_command(f"ip netns exec {NS} sysctl -w net.ipv4.ip_forward=1", check=False)
    
    # Masquerade (NAT)
    run_command(f"ip netns exec {NS} iptables -t nat -A POSTROUTING -o {real_if} -j MASQUERADE", check=False)
    
    # TCP MSS Clamping (Fixes Stalling/MTU issues)
    print("🔧 Optimizing TCP MSS for 5G Link...", flush=True)
    run_command(f"ip netns exec {NS} iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu", check=False)
    run_command(f"ip netns exec {NS} iptables -A FORWARD -i {VETH_BOX} -o {real_if} -j ACCEPT", check=False)
    run_command(f"ip netns exec {NS} iptables -A FORWARD -i {real_if} -o {VETH_BOX} -m state --state RELATED,ESTABLISHED -j ACCEPT", check=False)

    print("🔍 verifying connectivity...")
    if run_command(f"ip netns exec {NS} ping -c 1 8.8.8.8", check=False):
        print("🎉 Connected!")
        return True
    else:
        print("⚠️  Ping failed.")
        return False

def cmd_start(args):
    """Start the sandbox."""
    # ... (Keep existing profile logic) ...
    ssid = args.ssid
    password = args.password
    no_dhcp = args.no_dhcp
    static_ip = None
    gateway = None

    if args.profile:
        profiles = load_profiles()
        if args.profile not in profiles:
            print(f"❌ Profile '{args.profile}' not found.")
            sys.exit(1)
        p = profiles[args.profile]
        ssid = p["ssid"]
        password = p["password"]
        if "ip_address" in p:
             static_ip = p["ip_address"]
        if "gateway" in p:
             gateway = p["gateway"]
        mac_address = p.get("mac_address")
    elif not ssid or not password:
        print("❌ You must specify --profile OR --ssid and --password")
        sys.exit(1)

    if not start_sandbox(ssid, password, no_dhcp=no_dhcp, static_ip=static_ip, gateway=gateway, mac_address=mac_address):
        print("❌ Start failed.")
        sys.exit(1)

def cmd_monitor(args):
    """Watchdog mode: Monitor and Auto-Reconnect."""
    print(f"🛡️  Starting Watchdog for '{args.profile}'...")
    print("    Prees Ctrl+C to stop.")

    fail_count = 0
    while True:
        # Load profile fresh each loop (to pick up changes)
        profiles = load_profiles()
        if args.profile not in profiles:
             print(f"❌ Profile '{args.profile}' not found.")
             time.sleep(5)
             continue

        p = profiles[args.profile]
        ssid = p.get("ssid")
        password = p.get("password")
        static_ip = p.get("ip_address")
        gateway = p.get("gateway")
        mac_address = p.get("mac_address")
        
        # Initial Check (Is it running?)
        # If not running, Start it.
        # But wait, monitor assumes it manages the lifecycle.
        
        # Determine if we need to Start
        # We check connectivity. If fail, we start/restart.
        
        try:
            # Check Connectivity
            res = subprocess.run(f"ip netns exec {NS} ping -c 1 -W 2 8.8.8.8", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
            if res.returncode == 0:
                print("💚 Link Stable.", end="\r")
                fail_count = 0
                time.sleep(10)
            else:
                fail_count += 1
                if fail_count == 1:
                     print(f"⚠️  Link Down! ({fail_count}/3)       ")
                else:
                     print(f"⚠️  Link Down! ({fail_count}/3)       ", end="\r")
                
                if fail_count >= 3:
                    print("\n🔴 Connection Lost. Healing...")
                    # Full restart
                    cmd_stop(None)
                    time.sleep(2)
                    print("🩹 Re-initializing...")
                    start_sandbox(ssid, password, static_ip=static_ip, gateway=gateway, mac_address=mac_address)
                    fail_count = 0
                else:
                    time.sleep(2)
                    
        except KeyboardInterrupt:
            print("\n🛑 Stopping Watchdog.")
            break

def cmd_stop(args):
    """Stop and Clean up."""
    print("🧹 Cleaning up...")
    
    # Check if we can find PHY to return
    phy_inside = find_phy_in_ns(NS)
    if phy_inside:
        print(f"Returning '{phy_inside}' to host...")
        # Set down
        run_command(f"ip netns exec {NS} ip link set wlan0 down", check=False)
        # Move to PID 1
        run_command(f"ip netns exec {NS} iw phy {phy_inside} set netns 1")
    
    run_command(f"ip netns delete {NS}", check=False)
    run_command(f"ip link delete {VETH_HOST}", check=False)
    
    print("🔄 Restoring Host WiFi...")
    run_command("rfkill unblock wifi")
    # Attempt to bring up whatever wireless interface appears
    # (Simplified for portability)
    print("🎉 Cleanup Complete.")

def cmd_test(args):
    """Run stability test."""
    print("🧪 Running Stability Test inside Sandbox...")
    # We can embed the shell script logic here basically
    cmd = f"ip netns exec {NS} ping -c 5 8.8.8.8"
    print("\n--- Latency Test ---")
    os.system(cmd)
    
    print("\n--- SSL Handshake Test (5x) ---")
    for i in range(5):
        res = subprocess.run(f"ip netns exec {NS} curl -I -s https://generativelanguage.googleapis.com", shell=True)
        if res.returncode == 0: print("✅ SSL OK")
        else: print("❌ SSL FAIL")
        time.sleep(0.5)

def cmd_exec(args):
    """Execute command in sandbox."""
    # args.command is a list
    full_cmd = " ".join(args.command)
    print(f"💻 Executing: {full_cmd}")
    os.system(f"ip netns exec {NS} {full_cmd}")

def cmd_status(args):
    """Show sandbox status."""
    print("--- 📊 WiFiBox Status ---")
    
    # Check Namespace
    ns_list = run_command("ip netns list", check=False) or ""
    if NS in ns_list:
        print(f"✅ Namespace '{NS}': ACTIVE")
        
        # Check Interface
        wifi_if = run_command(f"ip netns exec {NS} iw dev", check=False)
        if wifi_if and "Interface" in wifi_if:
            match = re.search(r"Interface\s+(\S+)", wifi_if)
            iface = match.group(1) if match else "wlan0"
            print(f"   - Interface: {iface} (Up)")
            
            # Check Connection
            link = run_command(f"ip netns exec {NS} iw dev {iface} link", check=False)
            ssid_match = re.search(r"SSID:\s+(.*)", link)
            ssid = ssid_match.group(1) if ssid_match else "Disconnected"
            print(f"   - Connected to: {ssid}")
            
            # Check IP
            ip_info = run_command(f"ip netns exec {NS} ip -4 addr show {iface}", check=False)
            ip_match = re.search(r"inet\s+([\d\.]+)", ip_info)
            ip = ip_match.group(1) if ip_match else "No IP"
            print(f"   - IP Address: {ip}")
            
        else:
            print("   - Interface: ❌ Missing (PHY not in box?)")
            
        # Check PIDs
        pids = run_command(f"ip netns pids {NS}", check=False)
        if pids:
            count = len(pids.split())
            print(f"   - Processes: {count} running (PIDs: {pids})")
        else:
            print("   - Processes: 0")
            
    else:
        print(f"❌ Namespace '{NS}': NOT RUNNING")

# --- Main ---
def main():
    ensure_root()
    
    parser = argparse.ArgumentParser(description="WiFiBox: Portable Network Sandbox CLI")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Start
    p_start = subparsers.add_parser("start", help="Start the sandbox")
    p_start.add_argument("--ssid", help="WiFi SSID")
    p_start.add_argument("--password", help="WiFi Password")
    p_start.add_argument("--profile", help="Name of saved profile to use")
    p_start.add_argument("--no-dhcp", action="store_true", help="Skip DHCP and set static IP manually later")
    p_start.set_defaults(func=cmd_start)

    # Stop
    p_stop = subparsers.add_parser("stop", help="Stop/Cleanup")
    p_stop.set_defaults(func=cmd_stop)

    # Save
    p_save = subparsers.add_parser("save", help="Save a profile")
    p_save.add_argument("--name", required=True, help="Profile Name")
    p_save.add_argument("--ssid", required=True)
    p_save.add_argument("--password", required=True)
    p_save.set_defaults(func=cmd_save)

    # List
    p_list = subparsers.add_parser("list", help="List profiles")
    p_list.set_defaults(func=cmd_list)
    
    # Test
    p_test = subparsers.add_parser("test", help="Run stability tests")
    p_test.set_defaults(func=cmd_test)

    # Exec
    p_exec = subparsers.add_parser("exec", help="Run command inside sandbox")
    p_exec.add_argument("command", nargs=argparse.REMAINDER, help="Command to run")
    p_exec.set_defaults(func=cmd_exec)

    # Status
    p_status = subparsers.add_parser("status", help="Show status")
    p_status.set_defaults(func=cmd_status)

    # Monitor
    p_monitor = subparsers.add_parser("monitor", help="Auto-healing watchdog")
    p_monitor.add_argument("--profile", required=True, help="Profile to monitor")
    p_monitor.set_defaults(func=cmd_monitor)

    args = parser.parse_args()
    args.func(args)

if __name__ == "__main__":
    main()
