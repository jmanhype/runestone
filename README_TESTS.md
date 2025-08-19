# OpenAI API Integration Tests

This document describes the comprehensive test suite for the OpenAI API implementation in Runestone.

## Test Structure

### Test Categories

1. **Unit Tests** (`test/unit/`)
   - Individual function testing
   - Validation logic testing
   - Configuration handling
   - No external dependencies

2. **Integration Tests** (`test/integration/openai/`)
   - End-to-end API flow testing
   - Authentication integration
   - Provider routing
   - Error handling scenarios

3. **Support Files** (`test/support/`)
   - Test helpers and utilities
   - Mock configurations
   - Common test data

## Test Files Overview

### Integration Tests

- **`authentication_test.exs`** - Tests authentication flow, API key validation, rate limiting per key
- **`streaming_test.exs`** - Tests SSE parsing, chunk handling, real-time data flow
- **`rate_limiting_test.exs`** - Tests per-key limits, sliding windows, concurrent requests, overflow handling
- **`error_handling_test.exs`** - Tests various error scenarios and OpenAI-compatible error responses
- **`provider_routing_test.exs`** - Tests routing decisions, cost-aware routing, configuration handling
- **`end_to_end_test.exs`** - Complete request lifecycle testing from HTTP to provider response
- **`openai_provider_test.exs`** - Direct provider implementation testing

### Unit Tests

- **`openai_provider_unit_test.exs`** - Unit tests for OpenAI provider functions
- **`router_unit_test.exs`** - Unit tests for routing logic
- **`auth_middleware_unit_test.exs`** - Unit tests for authentication middleware

### Support Files

- **`test_helpers.exs`** - Common test utilities and helper functions
- **`openai_test_config.exs`** - Test configuration and environment setup

## Running Tests

### Quick Start

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/integration/openai/authentication_test.exs

# Run tests with specific tags
mix test --include integration
```

### Using the Test Runner Script

```bash
# Make script executable
chmod +x scripts/run_openai_tests.sh

# Run basic test suite
./scripts/run_openai_tests.sh

# Run with coverage and verbose output
./scripts/run_openai_tests.sh -v -c

# Run specific test categories
./scripts/run_openai_tests.sh auth streaming

# Run all tests including slow ones
./scripts/run_openai_tests.sh -a

# Quick unit tests only
./scripts/run_openai_tests.sh -q
```

### Test Categories

- `unit` - Unit tests only
- `integration` - Integration tests only
- `auth` - Authentication-related tests
- `streaming` - Streaming response tests
- `rate-limiting` - Rate limiting tests
- `error-handling` - Error handling tests
- `e2e` - End-to-end tests

## Test Configuration

### Environment Variables

The test suite uses several environment variables:

```bash
# API Configuration (test keys)
OPENAI_API_KEY=sk-test-openai-xxxxx
OPENAI_BASE_URL=https://api.openai.com/v1

# Router Configuration
RUNESTONE_ROUTER_POLICY=default

# Test Environment
MIX_ENV=test
RUNESTONE_ENV=test
```

### Test-Specific Configuration

Tests use isolated configuration defined in:
- `test/mix_test_config.exs` - Main test configuration
- `test/support/openai_test_config.exs` - OpenAI-specific test settings

## Test Coverage Areas

### 1. Authentication Flow
- ✅ Bearer token extraction and validation
- ✅ API key format verification
- ✅ Rate limiting per API key
- ✅ Error response formatting
- ✅ Security considerations

### 2. Streaming Responses
- ✅ SSE (Server-Sent Events) parsing
- ✅ JSON chunk processing
- ✅ Content accumulation
- ✅ Error handling in streams
- ✅ Unicode and special character support

### 3. Rate Limiting
- ✅ Requests per minute/hour limiting
- ✅ Concurrent request tracking
- ✅ Multi-tenant isolation
- ✅ Overflow handling and queueing
- ✅ Rate limit status reporting

### 4. Error Handling
- ✅ Authentication errors
- ✅ Request validation errors
- ✅ Network and timeout errors
- ✅ OpenAI API error format compliance
- ✅ Security error scenarios

### 5. Provider Routing
- ✅ Default routing policy
- ✅ Cost-aware routing
- ✅ Provider configuration loading
- ✅ Telemetry integration
- ✅ Edge case handling

### 6. End-to-End Integration
- ✅ Complete request lifecycle
- ✅ Health check endpoints
- ✅ Concurrent request handling
- ✅ Performance under load
- ✅ Memory usage stability

## Performance Testing

### Load Testing Scenarios

The test suite includes performance tests for:

- **Concurrent Requests**: 20-50 simultaneous requests
- **High Frequency**: 1000+ rapid sequential requests
- **Large Payloads**: Requests with 10MB+ data
- **Memory Stability**: Long-running test sessions

### Performance Assertions

- Response times under 100ms for simple requests
- Memory usage increase < 50MB during load tests
- Successful handling of 1000+ concurrent requests
- No memory leaks during extended operation

## Mock and Simulation

### HTTP Response Mocking

Tests include mocked responses for:
- Successful streaming responses
- Authentication errors (401)
- Rate limiting (429)
- Server errors (500)
- Network timeouts

### SSE Stream Simulation

Simulated streaming scenarios:
- Valid OpenAI streaming format
- Malformed JSON chunks
- Unicode content
- Large content blocks
- Connection interruptions

## Test Data

### Test API Keys

Generated test keys follow the pattern:
```
sk-test-{category}-{random}
```

### Test Messages

Predefined message sets for different scenarios:
- Simple single messages
- Multi-turn conversations
- Empty message arrays
- Large message sets (100+ messages)
- Unicode and special character content

### Test Models

Configured test models:
- `gpt-4o-mini` (default)
- `gpt-4o` (standard)
- `custom-model-name` (custom)
- `invalid-model-123` (invalid)

## Debugging Tests

### Verbose Output

```bash
# Enable verbose test output
mix test --trace

# Or using the script
./scripts/run_openai_tests.sh -v
```

### Test Isolation

Each test is designed to be independent:
- No shared state between tests
- Clean environment setup/teardown
- Isolated API key management
- Independent service instances

### Common Issues

1. **Test Timeouts**: Increase timeout for slow tests
2. **Service Dependencies**: Ensure required GenServers are started
3. **Environment Variables**: Check test environment configuration
4. **Concurrency Issues**: Use `async: false` for tests that need isolation

## Contributing to Tests

### Adding New Tests

1. Choose appropriate test category (unit vs integration)
2. Use existing test helpers and utilities
3. Follow naming conventions: `*_test.exs`
4. Include both positive and negative test cases
5. Add performance considerations for integration tests

### Test Guidelines

- **Isolation**: Tests should not depend on external services
- **Determinism**: Tests should produce consistent results
- **Performance**: Keep unit tests under 100ms
- **Coverage**: Aim for >80% code coverage
- **Documentation**: Include clear test descriptions

### Code Coverage

Generate coverage reports:

```bash
# HTML coverage report
mix coveralls.html

# Console coverage report
mix coveralls

# Coverage with specific format
mix coveralls.json
```

## Continuous Integration

The test suite is designed for CI/CD environments:

- **Parallel Execution**: Tests can run in parallel safely
- **Resource Limits**: Configurable concurrency limits
- **Environment Isolation**: No external service dependencies
- **Fast Feedback**: Unit tests complete in <30 seconds
- **Comprehensive Coverage**: Integration tests cover real-world scenarios

## Test Metrics

### Success Criteria

- ✅ All tests pass consistently
- ✅ >85% code coverage
- ✅ <1 minute total test execution time
- ✅ No memory leaks or resource retention
- ✅ Error scenarios properly handled

### Key Performance Indicators

- **Test Execution Time**: <60 seconds for full suite
- **Memory Usage**: <100MB peak during tests
- **Code Coverage**: >85% line coverage
- **Error Handling**: 100% of error scenarios covered
- **Concurrency**: Successfully handles 50+ concurrent requests

This test suite ensures the OpenAI API implementation is robust, secure, and performant under various conditions and load scenarios.