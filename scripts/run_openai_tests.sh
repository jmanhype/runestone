#!/bin/bash

# OpenAI API Integration Test Runner
# Runs comprehensive test suites for OpenAI API implementation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
VERBOSE=false
COVERAGE=false
PARALLEL=true
INTEGRATION=false
STRESS=false
QUICK=false

# Print usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  -v, --verbose     Enable verbose output"
    echo "  -c, --coverage    Run with coverage analysis"
    echo "  -s, --sequential  Run tests sequentially (default: parallel)"
    echo "  -i, --integration Include integration tests (slower)"
    echo "  -t, --stress      Run stress/load tests"
    echo "  -q, --quick       Run only unit tests (fastest)"
    echo "  -a, --all         Run all tests including slow ones"
    echo ""
    echo "Test Categories:"
    echo "  unit              Run unit tests only"
    echo "  integration       Run integration tests only"
    echo "  auth              Run authentication tests"
    echo "  streaming         Run streaming tests"
    echo "  rate-limiting     Run rate limiting tests"
    echo "  error-handling    Run error handling tests"
    echo "  e2e               Run end-to-end tests"
    echo ""
    echo "Examples:"
    echo "  $0                          # Run basic test suite"
    echo "  $0 -v -c                    # Verbose with coverage"
    echo "  $0 -i                       # Include integration tests"
    echo "  $0 unit                     # Run only unit tests"
    echo "  $0 auth streaming           # Run specific test categories"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -c|--coverage)
                COVERAGE=true
                shift
                ;;
            -s|--sequential)
                PARALLEL=false
                shift
                ;;
            -i|--integration)
                INTEGRATION=true
                shift
                ;;
            -t|--stress)
                STRESS=true
                shift
                ;;
            -q|--quick)
                QUICK=true
                shift
                ;;
            -a|--all)
                INTEGRATION=true
                STRESS=true
                shift
                ;;
            unit|integration|auth|streaming|rate-limiting|error-handling|e2e)
                TEST_CATEGORIES+=("$1")
                shift
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                exit 1
                ;;
        esac
    done
}

# Print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required dependencies are available
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v mix &> /dev/null; then
        log_error "Mix is not installed or not in PATH"
        exit 1
    fi
    
    if ! mix deps.get --only test 2>/dev/null; then
        log_warning "Could not fetch test dependencies"
    fi
    
    log_success "Dependencies OK"
}

# Set up test environment
setup_environment() {
    log_info "Setting up test environment..."
    
    # Set test environment variables
    export MIX_ENV=test
    export RUNESTONE_ENV=test
    
    # Set OpenAI test configuration
    export OPENAI_API_KEY="sk-test-$(openssl rand -hex 20)"
    export OPENAI_BASE_URL="https://api.openai.com/v1"
    export RUNESTONE_ROUTER_POLICY="default"
    
    # Compile test environment
    if ! mix compile --force; then
        log_error "Failed to compile test environment"
        exit 1
    fi
    
    log_success "Environment setup complete"
}

# Build test command
build_test_command() {
    local cmd="mix test"
    
    # Add coverage if requested
    if [[ "$COVERAGE" == "true" ]]; then
        cmd="mix coveralls.html"
    fi
    
    # Add verbosity
    if [[ "$VERBOSE" == "true" ]]; then
        cmd="$cmd --trace"
    fi
    
    # Configure parallelization
    if [[ "$PARALLEL" == "false" ]]; then
        cmd="$cmd --max-cases 1"
    fi
    
    # Add test inclusion/exclusion
    if [[ "$QUICK" == "true" ]]; then
        cmd="$cmd --exclude integration --exclude slow --exclude stress"
    elif [[ "$INTEGRATION" == "true" ]]; then
        cmd="$cmd --include integration"
    fi
    
    if [[ "$STRESS" == "true" ]]; then
        cmd="$cmd --include stress"
    fi
    
    echo "$cmd"
}

# Run specific test categories
run_category_tests() {
    local category=$1
    
    case $category in
        unit)
            log_info "Running unit tests..."
            mix test test/unit/ --exclude integration
            ;;
        integration)
            log_info "Running integration tests..."
            mix test test/integration/ --include integration
            ;;
        auth)
            log_info "Running authentication tests..."
            mix test test/integration/openai/authentication_test.exs test/unit/auth_middleware_unit_test.exs
            ;;
        streaming)
            log_info "Running streaming tests..."
            mix test test/integration/openai/streaming_test.exs
            ;;
        rate-limiting)
            log_info "Running rate limiting tests..."
            mix test test/integration/openai/rate_limiting_test.exs
            ;;
        error-handling)
            log_info "Running error handling tests..."
            mix test test/integration/openai/error_handling_test.exs
            ;;
        e2e)
            log_info "Running end-to-end tests..."
            mix test test/integration/openai/end_to_end_test.exs --include integration
            ;;
        *)
            log_error "Unknown test category: $category"
            return 1
            ;;
    esac
}

# Generate test report
generate_report() {
    log_info "Generating test report..."
    
    if [[ "$COVERAGE" == "true" ]] && [[ -d "cover" ]]; then
        log_info "Coverage report generated in cover/ directory"
        if command -v open &> /dev/null; then
            open cover/excoveralls.html
        fi
    fi
    
    log_success "Test execution completed"
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
    echo -e "${BLUE}🧪 OpenAI API Integration Test Suite${NC}"
    echo "========================================"
    
    parse_args "$@"
    check_dependencies
    setup_environment
    
    # Run tests
    if [[ ${#TEST_CATEGORIES[@]} -gt 0 ]]; then
        # Run specific categories
        for category in "${TEST_CATEGORIES[@]}"; do
            if ! run_category_tests "$category"; then
                log_error "Tests failed for category: $category"
                exit 1
            fi
        done
    else
        # Run full test suite
        local test_cmd=$(build_test_command)
        log_info "Running: $test_cmd"
        
        if ! eval "$test_cmd"; then
            log_error "Test suite failed"
            exit 1
        fi
    fi
    
    generate_report
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "All tests completed successfully in ${duration}s"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    TEST_CATEGORIES=()
    main "$@"
fi