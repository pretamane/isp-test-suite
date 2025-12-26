#!/bin/bash
set -e

# Ensure Root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

LOG_FILE="verification_results.txt"

echo "🧪 Starting Maharnet 5G Optimization Verification..." | tee -a "$LOG_FILE"
echo "Date: $(date)" | tee -a "$LOG_FILE"
echo "---------------------------------------------------" | tee -a "$LOG_FILE"

# 1. Setup Sandbox
echo "📦 1. Setting up Sandbox..." | tee -a "$LOG_FILE"
./sandbox_wifi.sh | tee -a "$LOG_FILE"

# 2. Baseline Test
echo "" | tee -a "$LOG_FILE"
echo "📉 2. Running BASELINE Health Check..." | tee -a "$LOG_FILE"
echo "-------------------------------------" | tee -a "$LOG_FILE"
ip netns exec internet_box ./health_check.sh | tee -a "$LOG_FILE"

# 3. Apply Tuning
echo "" | tee -a "$LOG_FILE"
echo "🔧 3. Applying Network Enhancements (Inside Namespace)..." | tee -a "$LOG_FILE"
# Copy script to ensure it's accessible or just run from current path if mapped? 
# Namespaces share filesystem usually, so path is fine.
ip netns exec internet_box ./tune_network.sh | tee -a "$LOG_FILE"

# 4. Tuned Test
echo "" | tee -a "$LOG_FILE"
echo "📈 4. Running TUNED Health Check..." | tee -a "$LOG_FILE"
echo "----------------------------------" | tee -a "$LOG_FILE"
ip netns exec internet_box ./health_check.sh | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "🎉 Verification Complete. Full log saved to $LOG_FILE" | tee -a "$LOG_FILE"
