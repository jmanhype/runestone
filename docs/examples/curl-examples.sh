#!/bin/bash

# Runestone API Examples using cURL
# These examples demonstrate the various endpoints and features of the Runestone API

# Set your API endpoint and key
RUNESTONE_API_URL="${RUNESTONE_API_URL:-http://localhost:4001}"
API_KEY="${RUNESTONE_API_KEY:-your-api-key-here}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function to print section headers
print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Helper function to print commands
print_command() {
    echo -e "${YELLOW}Command:${NC} $1"
}

print_section "Runestone API Examples"
echo "API URL: $RUNESTONE_API_URL"
echo "Replace 'your-api-key-here' with your actual API key"

# Example 1: Basic Chat Completion
print_section "1. Basic Chat Completion"
print_command "curl -X POST $RUNESTONE_API_URL/v1/chat/completions"

curl -X POST "$RUNESTONE_API_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {
        "role": "system",
        "content": "You are a helpful assistant."
      },
      {
        "role": "user", 
        "content": "What is the capital of France?"
      }
    ],
    "max_tokens": 100,
    "temperature": 0.7
  }' | jq '.'

echo -e "\n${GREEN}✓ Basic chat completion request sent${NC}"

# Example 2: Streaming Chat (Runestone-specific endpoint)
print_section "2. Streaming Chat Completion"
print_command "curl -N -X POST $RUNESTONE_API_URL/v1/chat/stream"

echo "Starting streaming request (press Ctrl+C to stop)..."
curl -N -X POST "$RUNESTONE_API_URL/v1/chat/stream" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "provider": "openai",
    "model": "gpt-4o-mini",
    "messages": [
      {
        "role": "user",
        "content": "Tell me a short joke about programming"
      }
    ],
    "tenant_id": "example-tenant"
  }'

echo -e "\n${GREEN}✓ Streaming chat request completed${NC}"

# Example 3: OpenAI-compatible Streaming
print_section "3. OpenAI-compatible Streaming"
print_command "curl -N -X POST $RUNESTONE_API_URL/v1/chat/completions with stream=true"

curl -N -X POST "$RUNESTONE_API_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {
        "role": "user",
        "content": "Count from 1 to 5"
      }
    ],
    "stream": true,
    "max_tokens": 50
  }'

echo -e "\n${GREEN}✓ OpenAI-compatible streaming request completed${NC}"

# Example 4: Cost-aware Routing
print_section "4. Cost-aware Routing"
print_command "curl with cost optimization parameters"

curl -X POST "$RUNESTONE_API_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "messages": [
      {
        "role": "user",
        "content": "Summarize the main benefits of renewable energy"
      }
    ],
    "model_family": "general",
    "capabilities": ["chat", "streaming"],
    "max_cost_per_token": 0.0001,
    "tenant_id": "cost-conscious-tenant"
  }' | jq '.'

echo -e "\n${GREEN}✓ Cost-aware routing request sent${NC}"

# Example 5: Provider-specific Request
print_section "5. Provider-specific Request"
print_command "curl with explicit provider specification"

curl -X POST "$RUNESTONE_API_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "provider": "anthropic",
    "model": "claude-3-5-sonnet",
    "messages": [
      {
        "role": "user",
        "content": "Explain quantum computing in simple terms"
      }
    ],
    "max_tokens": 200,
    "tenant_id": "research-team"
  }' | jq '.'

echo -e "\n${GREEN}✓ Provider-specific request sent${NC}"

# Example 6: List Models
print_section "6. List Available Models"
print_command "curl -X GET $RUNESTONE_API_URL/v1/models"

curl -X GET "$RUNESTONE_API_URL/v1/models" \
  -H "Authorization: Bearer $API_KEY" | jq '.'

echo -e "\n${GREEN}✓ Models list retrieved${NC}"

# Example 7: Get Specific Model
print_section "7. Get Model Details"
print_command "curl -X GET $RUNESTONE_API_URL/v1/models/gpt-4o-mini"

curl -X GET "$RUNESTONE_API_URL/v1/models/gpt-4o-mini" \
  -H "Authorization: Bearer $API_KEY" | jq '.'

echo -e "\n${GREEN}✓ Model details retrieved${NC}"

# Example 8: Health Check
print_section "8. System Health Check"
print_command "curl -X GET $RUNESTONE_API_URL/health"

curl -X GET "$RUNESTONE_API_URL/health" | jq '.'

echo -e "\n${GREEN}✓ Health check completed${NC}"

# Example 9: Liveness Probe
print_section "9. Liveness Probe"
print_command "curl -X GET $RUNESTONE_API_URL/health/live"

curl -X GET "$RUNESTONE_API_URL/health/live" | jq '.'

echo -e "\n${GREEN}✓ Liveness probe completed${NC}"

# Example 10: Readiness Probe  
print_section "10. Readiness Probe"
print_command "curl -X GET $RUNESTONE_API_URL/health/ready"

curl -X GET "$RUNESTONE_API_URL/health/ready" | jq '.'

echo -e "\n${GREEN}✓ Readiness probe completed${NC}"

# Example 11: Rate Limit Testing
print_section "11. Rate Limit Testing"
print_command "Multiple concurrent requests to test rate limiting"

echo "Sending 5 concurrent requests to test rate limiting..."
for i in {1..5}; do
  curl -X POST "$RUNESTONE_API_URL/v1/chat/stream" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
      "messages": [
        {
          "role": "user",
          "content": "Test message #'$i'"
        }
      ],
      "model": "gpt-4o-mini",
      "tenant_id": "rate-limit-test"
    }' > /dev/null 2>&1 &
done

wait
echo -e "\n${GREEN}✓ Rate limit testing completed${NC}"

# Example 12: Error Handling
print_section "12. Error Handling Examples"

echo "Testing invalid request (missing messages):"
curl -X POST "$RUNESTONE_API_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "gpt-4o-mini"
  }' | jq '.'

echo -e "\nTesting invalid model:"
curl -X POST "$RUNESTONE_API_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "nonexistent-model",
    "messages": [
      {
        "role": "user",
        "content": "Hello"
      }
    ]
  }' | jq '.'

echo -e "\n${GREEN}✓ Error handling examples completed${NC}"

print_section "Examples Complete"
echo -e "${GREEN}All Runestone API examples have been executed!${NC}"
echo -e "${YELLOW}Note: Some requests may fail if the server is not running or API keys are invalid.${NC}"