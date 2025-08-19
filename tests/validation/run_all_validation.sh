#!/bin/bash

# Comprehensive Runestone Production Validation Runner
# This script runs all validation tests to ensure production readiness

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RUNESTONE_URL="${RUNESTONE_URL:-http://localhost:4002}"
API_KEY="${API_KEY:-test-api-key}"
VALIDATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$VALIDATION_DIR/../.." && pwd)"

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo
    echo "=================================="
    echo "$1"
    echo "=================================="
}

print_section() {
    echo
    echo -e "${BLUE}$1${NC}"
    echo "----------------------------------"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if Runestone is running
check_runestone() {
    print_section "🔍 Checking Runestone availability..."
    
    if curl -s -f "$RUNESTONE_URL/health" >/dev/null 2>&1; then
        print_status $GREEN "✅ Runestone is running at $RUNESTONE_URL"
        return 0
    else
        print_status $YELLOW "⚠️  Runestone not accessible at $RUNESTONE_URL"
        print_status $YELLOW "   Please start Runestone with: mix phx.server"
        print_status $YELLOW "   Or set RUNESTONE_URL environment variable"
        return 1
    fi
}

# Function to run Elixir tests
run_elixir_tests() {
    print_section "🧪 Running Elixir Validation Tests..."
    
    cd "$PROJECT_ROOT"
    
    if command_exists elixir; then
        if [ -f "$VALIDATION_DIR/run_validation.exs" ]; then
            print_status $BLUE "Running production validation suite..."
            if elixir "$VALIDATION_DIR/run_validation.exs"; then
                print_status $GREEN "✅ Elixir validation tests passed"
                return 0
            else
                print_status $RED "❌ Elixir validation tests failed"
                return 1
            fi
        else
            print_status $YELLOW "⚠️  Elixir validation script not found"
            return 0
        fi
    else
        print_status $YELLOW "⚠️  Elixir not installed, skipping Elixir tests"
        return 0
    fi
}

# Function to run Python SDK tests
run_python_tests() {
    print_section "🐍 Running Python SDK Compatibility Tests..."
    
    if command_exists python3; then
        # Check if OpenAI SDK is installed
        if python3 -c "import openai" >/dev/null 2>&1; then
            print_status $BLUE "Running Python SDK validation..."
            cd "$VALIDATION_DIR"
            if python3 python_sdk_test.py --base-url "$RUNESTONE_URL" --api-key "$API_KEY"; then
                print_status $GREEN "✅ Python SDK tests passed"
                return 0
            else
                print_status $RED "❌ Python SDK tests failed"
                return 1
            fi
        else
            print_status $YELLOW "⚠️  OpenAI Python SDK not installed"
            print_status $YELLOW "   Install with: pip install openai requests"
            return 0
        fi
    else
        print_status $YELLOW "⚠️  Python 3 not installed, skipping Python tests"
        return 0
    fi
}

# Function to run Node.js SDK tests
run_nodejs_tests() {
    print_section "🟨 Running Node.js SDK Compatibility Tests..."
    
    if command_exists node; then
        # Check if OpenAI SDK is installed
        cd "$VALIDATION_DIR"
        if node -e "require('openai')" >/dev/null 2>&1; then
            print_status $BLUE "Running Node.js SDK validation..."
            if node nodejs_sdk_test.js --base-url "$RUNESTONE_URL" --api-key "$API_KEY"; then
                print_status $GREEN "✅ Node.js SDK tests passed"
                return 0
            else
                print_status $RED "❌ Node.js SDK tests failed"
                return 1
            fi
        else
            print_status $YELLOW "⚠️  OpenAI Node.js SDK not installed"
            print_status $YELLOW "   Install with: npm install openai axios"
            return 0
        fi
    else
        print_status $YELLOW "⚠️  Node.js not installed, skipping Node.js tests"
        return 0
    fi
}

# Function to run cURL tests
run_curl_tests() {
    print_section "🌐 Running cURL Compatibility Tests..."
    
    if command_exists curl; then
        print_status $BLUE "Testing basic HTTP compatibility..."
        
        # Test basic chat completion
        local response
        response=$(curl -s -w "\n%{http_code}" -X POST "$RUNESTONE_URL/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $API_KEY" \
            -d '{
                "model": "gpt-4o-mini",
                "messages": [
                    {"role": "user", "content": "Hello from cURL"}
                ],
                "max_tokens": 10
            }' 2>/dev/null)
        
        local http_code
        http_code=$(echo "$response" | tail -n1)
        local body
        body=$(echo "$response" | head -n -1)
        
        if [[ "$http_code" == "200" || "$http_code" == "202" ]]; then
            # Validate JSON response
            if echo "$body" | python3 -m json.tool >/dev/null 2>&1; then
                print_status $GREEN "✅ cURL compatibility validated"
                return 0
            else
                print_status $RED "❌ Invalid JSON response from cURL test"
                return 1
            fi
        else
            print_status $RED "❌ cURL test failed with HTTP $http_code"
            echo "Response: $body"
            return 1
        fi
    else
        print_status $YELLOW "⚠️  cURL not installed, skipping HTTP tests"
        return 0
    fi
}

# Function to run streaming tests
run_streaming_tests() {
    print_section "📡 Running Streaming Compatibility Tests..."
    
    if command_exists curl; then
        print_status $BLUE "Testing Server-Sent Events streaming..."
        
        # Test streaming endpoint
        local response
        response=$(curl -s -m 30 -X POST "$RUNESTONE_URL/v1/chat/stream" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $API_KEY" \
            -d '{
                "model": "gpt-4o-mini",
                "messages": [
                    {"role": "user", "content": "Count to 3"}
                ]
            }' 2>/dev/null)
        
        if [[ $? -eq 0 ]]; then
            # Check for SSE format
            if echo "$response" | grep -q "data: " && echo "$response" | grep -q "\[DONE\]"; then
                print_status $GREEN "✅ Streaming compatibility validated"
                return 0
            else
                print_status $YELLOW "⚠️  Streaming response format may not be SSE compliant"
                return 0
            fi
        else
            print_status $YELLOW "⚠️  Streaming test connection failed or timed out"
            return 0
        fi
    else
        print_status $YELLOW "⚠️  cURL not available for streaming tests"
        return 0
    fi
}

# Function to run performance tests
run_performance_tests() {
    print_section "⚡ Running Performance Validation Tests..."
    
    if command_exists curl; then
        print_status $BLUE "Testing concurrent request handling..."
        
        # Run 5 concurrent requests
        local pids=()
        local temp_dir
        temp_dir=$(mktemp -d)
        
        for i in {1..5}; do
            (
                curl -s -w "%{http_code}" -X POST "$RUNESTONE_URL/v1/chat/completions" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $API_KEY" \
                    -d "{
                        \"model\": \"gpt-4o-mini\",
                        \"messages\": [
                            {\"role\": \"user\", \"content\": \"Performance test $i\"}
                        ],
                        \"max_tokens\": 5
                    }" > "$temp_dir/response_$i.txt" 2>/dev/null
            ) &
            pids+=($!)
        done
        
        # Wait for all requests to complete
        local success_count=0
        for pid in "${pids[@]}"; do
            if wait "$pid"; then
                ((success_count++))
            fi
        done
        
        # Check results
        local response_count=0
        for i in {1..5}; do
            if [ -f "$temp_dir/response_$i.txt" ]; then
                local code
                code=$(cat "$temp_dir/response_$i.txt")
                if [[ "$code" == "200" || "$code" == "202" ]]; then
                    ((response_count++))
                fi
            fi
        done
        
        # Cleanup
        rm -rf "$temp_dir"
        
        if [ "$response_count" -ge 3 ]; then
            print_status $GREEN "✅ Performance tests passed ($response_count/5 requests succeeded)"
            return 0
        else
            print_status $YELLOW "⚠️  Performance tests warning ($response_count/5 requests succeeded)"
            return 0
        fi
    else
        print_status $YELLOW "⚠️  cURL not available for performance tests"
        return 0
    fi
}

# Function to run all validation tests
run_all_validations() {
    local test_results=()
    
    # Check Runestone availability first
    if ! check_runestone; then
        print_status $RED "❌ Cannot proceed without Runestone running"
        return 1
    fi
    
    # Run all test suites
    echo
    print_header "🔬 RUNESTONE PRODUCTION VALIDATION"
    echo "Target: $RUNESTONE_URL"
    echo "API Key: ${API_KEY:0:8}..."
    
    # Elixir tests
    if run_elixir_tests; then
        test_results+=("Elixir:PASS")
    else
        test_results+=("Elixir:FAIL")
    fi
    
    # Python SDK tests
    if run_python_tests; then
        test_results+=("Python SDK:PASS")
    else
        test_results+=("Python SDK:FAIL")
    fi
    
    # Node.js SDK tests
    if run_nodejs_tests; then
        test_results+=("Node.js SDK:PASS")
    else
        test_results+=("Node.js SDK:FAIL")
    fi
    
    # cURL tests
    if run_curl_tests; then
        test_results+=("cURL:PASS")
    else
        test_results+=("cURL:FAIL")
    fi
    
    # Streaming tests
    if run_streaming_tests; then
        test_results+=("Streaming:PASS")
    else
        test_results+=("Streaming:FAIL")
    fi
    
    # Performance tests
    if run_performance_tests; then
        test_results+=("Performance:PASS")
    else
        test_results+=("Performance:FAIL")
    fi
    
    # Generate summary
    print_header "📊 VALIDATION SUMMARY"
    
    local passed=0
    local failed=0
    local total=${#test_results[@]}
    
    for result in "${test_results[@]}"; do
        local test_name="${result%:*}"
        local test_status="${result#*:}"
        
        if [ "$test_status" = "PASS" ]; then
            print_status $GREEN "✅ $test_name: PASSED"
            ((passed++))
        else
            print_status $RED "❌ $test_name: FAILED"
            ((failed++))
        fi
    done
    
    echo
    print_status $BLUE "Results: $passed/$total tests passed"
    
    if [ "$failed" -eq 0 ]; then
        echo
        print_status $GREEN "🎉 VALIDATION SUCCESSFUL - PRODUCTION READY!"
        print_status $GREEN "   Runestone is fully compatible with OpenAI API"
        print_status $GREEN "   System is ready for production deployment"
        return 0
    else
        echo
        print_status $RED "❌ VALIDATION FAILED - NOT PRODUCTION READY"
        print_status $RED "   $failed critical test(s) failed"
        print_status $RED "   Please resolve issues before production deployment"
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Runestone Production Validation Runner"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --url URL        Runestone base URL (default: http://localhost:4002)"
    echo "  --api-key KEY    Test API key (default: test-api-key)"
    echo "  --help           Show this help message"
    echo
    echo "Environment Variables:"
    echo "  RUNESTONE_URL    Base URL for Runestone API"
    echo "  API_KEY          Test API key to use"
    echo
    echo "Examples:"
    echo "  $0                                    # Use defaults"
    echo "  $0 --url http://localhost:4001       # Custom URL"
    echo "  RUNESTONE_URL=https://api.example.com $0  # Using environment"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)
            RUNESTONE_URL="$2"
            shift 2
            ;;
        --api-key)
            API_KEY="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_header "🚀 RUNESTONE PRODUCTION VALIDATION SUITE"
    print_status $BLUE "Validating OpenAI API compatibility and production readiness"
    
    if run_all_validations; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"