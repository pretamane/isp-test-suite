#!/bin/bash
set -e

# Usage: ./test_real_agent.sh YOUR_API_KEY
API_KEY="$1"

if [ -z "$API_KEY" ]; then
    echo "❌ Error: API Key required."
    echo "Usage: $0 YOUR_API_KEY"
    exit 1
fi

# Generative Language API (Gemini Direct)
API_URL="https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?key=${API_KEY}"

MODEL_PAYLOAD='{
  "contents": [{
    "parts": [{
      "text": "Write a very long, detailed science fiction story about a network engineer troubleshooting a 5G connection on Mars. It should be at least 1000 words. Keep writing until finished."
    }]
  }]
}'

echo "🤖 Connecting to Gemini API (Key Auth)..."
echo "======================================================"
echo "Endpoint: $API_URL"
echo "Prompt: Writing a long story about a network engineer on Mars..."
echo "------------------------------------------------------"
echo "⬇️  Streaming Response (Raw Chunks):"

# Use curl with unbuffered output (-N)
# We capture stderr to check for HTTP codes if needed, but for now we just dump the output.
# If an error object is returned, it usually comes as a single JSON blob, not a stream.

echo "   ... connecting ..."
RESPONSE=$(curl -s -N -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -d "$MODEL_PAYLOAD")

# Check if response contains "error"
if [[ "$RESPONSE" == *"error"* ]]; then
    echo ""
    echo "❌ API returned an error:"
    echo "$RESPONSE"
    exit 1
else
    # It might be a valid stream (NDJSON or similar), but for Gemini streamGenerateContent it's a list of JSON objects
    # We'll just print it raw or length to show it worked.
    echo "$RESPONSE" | while IFS= read -r line; do
        printf "."
    done
    echo ""
    echo "✅ Stream finished (Length: ${#RESPONSE} bytes)"
fi
