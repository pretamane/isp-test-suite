# ISP Test Suite: Methodological Walkthrough & Case Study
**Subject:** Resolving MaHarNet 5G "Stalls" via Sandbox Isolation & MSS Clamping

This guide details the **Phased Methodology** used to diagnose and fix the "Silent Drop" issue on the MaHarNet 5G network. It explains *how* and *why* we used each tool in the `isp-test-suite`.

---

## Phase 1: Isolation (The Sandbox)
**Goal:** Test the "Raw" WiFi connection without breaking the Host's internet (USB Tether).

1.  **Why Sandbox?**
    - Taking down the main interface to debug WiFi is risky (loss of control).
    - We used `wifibox` (Network Namespaces) to move the *Physical WiFi Card* (`wlp1s0`) into an isolated container (`internet_box`).
    - **Result:** Host uses USB Tether (Safe), Sandbox uses WiFi (Test Subject).

2.  **Key Tools:**
    - `wifibox.py start`: Creates namespace, moves adapter, connects to WiFi.
    - `mhnsb on`: Wrapper script to automate the above.

---

## Phase 2: Diagnosis (Reproducing the Stall)
**Goal:** Prove the "Stall" exists scientifically.

1.  **The Test:**
    - We simulated a "Heavy Application" (like an AI Agent) sending a large JSON payload (~5KB).
    - **Tool:** `simulate_stall.sh`
2.  **Observation:**
    - Small packets (Ping) -> **Pass**.
    - Large packets (Application) -> **TIMEOUT** (The "Stall").
3.  **Discovery:**
    - The ISP drops packets >1400 bytes but sends no error signal (Blackhole).

---

## Phase 3: Tuning (Finding the Fix)
**Goal:** Find the magic numbers that prevent the stall.

1.  **Method:**
    - We lowered the **MTU** (Maximum Transmission Unit) inside the sandbox until the stall disappeared.
2.  **Results:**
    - MTU 1500 -> **Fail**.
    - MTU 1400 -> **Fail**.
    - MTU 1360 -> **PASS**.
3.  **The Fix:**
    - We applied **TCP MSS Clamping** to 1320 bytes. This forces the application to cut its data into small chunks *before* sending, bypassing the ISP's limit.
    - **Command:** `iptables ... -j TCPMSS --set-mss 1320`.

---

## Phase 4: Migration (Applying to Host)
**Goal:** Apply the proven Sandbox settings to the Real Machine.

1.  **The Switch:**
    - We stopped the sandbox (`wifibox.py stop`) to return importance `wlp1s0` to the Host.
2.  **Automation:**
    - **Tool:** `optimize_host_network.sh` (or `99-optimize-maharnet`).
    - This script automatically detects when MaHarNet connects and injects the **Iptables MSS Rule (1320)** into the Host Kernel.
3.  **Verification:**
    - `simulate_stall.sh` run on the *Host* finally PASSED (246ms).

---

## Phase 5: Deep Verification (Health Check)
**Goal:** Confirm stability vs Congestion.

1.  **The Problem:**
    - Connection was fixed (no stalls) but still "laggy".
2.  **Diagnostics:**
    - **Tool:** `health_check.sh`
    - **Result:**
        - Gateway Ping: 0% Loss (Hardware OK).
        - Google Ping: 10% Loss (ISP Congestion).
    - **Conclusion:** The Driver/Card is fine. The ISP is congested, but thanks to Phase 4, the congestion *no longer causes timeouts*, just minor lag.

---

## Summary of Tools
| Tool | Purpose | Phase |
| :--- | :--- | :--- |
| `wifibox.py` | Manages Sandbox Isolation | Phase 1 |
| `simulate_stall.sh` | Reproduces the Blackhole Bug | Phase 2 |
| `optimize_host_network.sh` | Applies Fix to Real Laptop | Phase 4 |
| `health_check.sh` | Validates Latency/Jitter/Speed | Phase 5 |
| `maharnet_soc_report.md` | Final Report for ISP submission | Output |
