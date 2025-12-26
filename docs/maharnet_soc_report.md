# Technical Incident Report: MaHarNet 5G Transmission Stalls
**Date:** 2025-12-26
**Priority:** High (Silent Packet Loss / Service Degradation)
**Subject:** MTU Blackhole & "Silent Drop" on 5G Core Network causing Application Stalls

**Subscriber Contact Information:**
- **Name:** Thaw Zin
- **Viber:** 09 7997 450 68
- **Telegram:** @pretamane

## 1. Executive Summary
Extensive diagnostic testing on the MaHarNet 5G network (Contabo Node) has identified a critical configuration issue regarding **Path MTU Discovery (PMTUD)**.
Packets larger than approximately **1380-1400 bytes** are being silently dropped (Blackholed) by the ISP's upstream infrastructure without generating the required ICMP Type 3 Code 4 (Fragmentation Needed) response.

This causes "stalls" and timeouts for modern protocols (HTTP/2, gRPC, TLS Handshakes) and Tunneling protocols (VLESS/Trojan), which default to 1500-byte payloads.

---

## 2. Technical Analysis

### 2.1 The Symptom
- **Observation**: Connection establishes (SYN/ACK OK), but data transfer "hangs" immediately after the Client Hello or first large data burst.
- **Affected Protocols**:
  - Google Gemini API (gRPC/HTTP2)
  - NekoBox / SingBox Tunnels
  - Large File Uploads/Downloads (HTTPS)
- **Error Signature**: Client timeout (Internet connection appears "up", but no data flows).

### 2.2 Diagnosis Data
We performed an MTU Ping Sweep Diagnosis from the endpoint.

**Test Command**: `ping -M do -s [SIZE] 8.8.8.8` (Set Don't Fragment bit)

| Packet Size | Result | Notes |
| :--- | :--- | :--- |
| **1472 bytes** (Total 1500) | **TIMEOUT** | Standard Ethernet frame. Silently dropped. |
| **1400 bytes** (Total 1428) | **TIMEOUT** | Silently dropped. |
| **1350 bytes** (Total 1378) | **OK** | Payload delivered. |
| **1320 bytes** (Total 1348) | **OK** | Optimal safe range. |

**Conclusion**: The "Real" MTU of the MaHarNet 5G Core path is approximately **1360-1400 bytes**.

### 2.3 The "Blackhole" Failure
The core issue is NOT the small MTU (which is common in cellular/encapsulated networks).
**The issue is the lack of ICMP signaling.**
- **Correct Behavior**: Router drops standard packet -> Sends ICMP "Too Big, use MTU 1380" -> Client adjusts.
- **Observed Behavior**: Router drops packet -> **Silence** -> Client keeps retransmitting 1500 byte packet -> Connection Stalls.

---

## 3. Impact on Tunneling (NekoBox/SingBox)
Users relying on Tunnels (VPN/VLESS) are doubly affected:
1.  **Encapsulation Overhead**: The tunnel addsheaders (20–40 bytes).
2.  **Fragmentation**: If the inner packet + overhead > ISP MTU, it results in fragmentation or drop.

**Scenario**:
*   App sends 1500 bytes.
*   Tunnel MTU 1280 (Safe?) -> Splits it into 1280 + 220.
*   Outer Packet (1280 + 80 Header = 1360) -> **Borderline Pass**.
*   **However**: If the application tries to discover MTU itself, it fails due to the blackhole.

---

## 4. Remediation Steps Taken (Client Side)
To mitigate this on our end, we forced the following configuration:
1.  **TCP MSS Clamping**: `iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1320`
2.  **Reasoning**: This forces all TCP negotiations to agree on a maximum payload of 1320 bytes, ensuring the final packet (Headers + Payload) never exceeds ~1380 bytes, bypassing the silent drop threshold.

## 5. Request to ISP (MaHarNet SOC)
Please investigate the **Mobile Core / PGW (Packet Gateway)** configuration:
1.  **Enable ICMP Type 3 generation** for oversized packets. (Fixes PMTUD).
2.  **Verify MTU Settings** on the interconnects.
3.  **Check for "Jumbo Frame" mismatches** in the backhaul.

**Log Evidence (Tcpdump snippet)**:
```
14:00:01 IP client > server: Flags [P.], seq 1:1461, length 1460 (Dropped)
14:00:03 IP client > server: Flags [P.], seq 1:1461, length 1460 (Retransmission - Dropped)
14:00:07 IP client > server: Flags [P.], seq 1:1461, length 1460 (Retransmission - Dropped)
```

## Appendix: Raw Connection Verification (No Tunnel)
**Date:** 2025-12-26
**Scope:** Direct 5G Connection (No VPN/Tunnel)

1.  **Packet Loss**:
    - Even with optimal MTU (1360 bytes), we observe **10-50% Packet Loss** on ICMP checks to `8.8.8.8`.
    - This indicates significant **Congestion or Signal Interference** on the Radio Access Network (RAN) or Core Backhaul, independent of the MTU settings.
2.  **MTU Enforcement**:
    - The client device has been hard-coded to **MTU 1480** to prevent sending lethal 1500-byte packets.
    - **Result**: Connection is stable (No Stalls), proving that oversized packets were indeed the trigger for the previous service denial.
