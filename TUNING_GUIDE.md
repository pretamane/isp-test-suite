# MaHarNet 5G Optimization Guide

This guide explains how to use the global tools installed on your system to manage the "MaHarNet 5G" connection and anti-stall tuning.

## 🚀 Global Command Cheat Sheet

We have installed two tools for you (`mhnf` and `mhnsb`). You can run these from any folder (e.g., in `bash` or `zsh`).

### 🛠 `mhnf` (MaHarNet Fix) - Network Tuning
Controls the Anti-Stall optimizations (MSS Clamping, BBR, Driver Settings).

| Command | Description |
| :--- | :--- |
| `mhnf on` | **Turn ON** optimizations. Makes them permanent (survives reboot). |
| `mhnf off` | **Turn OFF** optimizations. Removes permanent config and reverts settings. |
| `mhnf status` | **Check Status**. Shows if optimizations are currently active. |

---

### 📦 `mhnsb` (MaHarNet Sandbox) - WiFi Isolation
Controls the Network Sandbox (isolating the WiFi adapter so it doesn't conflict with Ethernet).

| Command | Description |
| :--- | :--- |
| `mhnsb on` | **Enable Sandbox**. Moves WiFi adapter (`phy1`) INSIDE the isolated namespace. |
| `mhnsb off` | **Disable Sandbox**. Pulls WiFi adapter OUT and returns it to the host. |

> **Note:** `mhnsb` requires `sudo`. Our alias handles this, but if it fails, try `sudo mhnsb on`.

---

## Technical Details

### 1. What Does `mhnf` Do?
To fix the "loading forever" (stalling) issues on 5G, `mhnf` applies:
1.  **MSS Clamping (Anti-Stall):** Shrinks packet headers to fit the cellular network pipe (`iptables`).
2.  **TCP MTU Probing:** Kernel automatically detects and fixes dropped packets (`sysctl`).
3.  **Driver Tweak:** Disables WiFi Power Save to prevent lag spikes (`iw`).

When you run `mhnf on`, it writes these settings to `/etc/sysctl.d/99-maharnet.conf` and `/etc/rc.local` so they stay active forever.

### 2. Manual Installation (If needed)
If the global commands ever disappear, you can reinstall them:
```bash
cd /home/guest/tzdump/isp-test-suite
sudo ./install_persistence.sh
chmod +x mhnf mhnsb
sudo ln -sf $(pwd)/mhnf /usr/local/bin/mhnf
sudo ln -sf $(pwd)/mhnsb /usr/local/bin/mhnsb
```

### 3. Verification
To verify everything is working:
1.  **Check Status:** `mhnf status` should show "ACTIVE".
2.  **Test Stream:** Run `sudo ip netns exec internet_box ./simulate_stream.sh` (if sandboxed) to confirm no stalls.
