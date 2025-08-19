#!/bin/bash

# Test Runestone with Anthropic API
echo "🧪 Testing Runestone + Anthropic Integration"
echo "============================================"

# Test endpoint availability
echo -e "\n1️⃣ Testing endpoint availability..."
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:4003/health

# Test with Anthropic model
echo -e "\n2️⃣ Testing Anthropic Claude through Runestone..."
response=$(curl -s -X POST http://localhost:4003/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-key" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [
      {"role": "user", "content": "Reply with exactly: Hello from Runestone with Claude!"}
    ],
    "max_tokens": 50,
    "stream": false
  }')

echo "Response:"
echo "$response" | jq '.' 2>/dev/null || echo "$response"

# Check if response contains expected content
if echo "$response" | grep -q "Hello from Runestone"; then
    echo -e "\n✅ SUCCESS: Anthropic integration is working!"
else
    echo -e "\n❌ Response doesn't contain expected message"
fi

echo -e "\n============================================"
echo "Test complete!"