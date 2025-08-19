# Mix Test Configuration for OpenAI API Integration Tests

# Import all test configuration
import_config "../config/config.exs"

# Test-specific configuration
config :runestone,
  environment: :test,
  test_mode: true

# HTTP Client configuration for testing
config :runestone, :http_client,
  timeout: 30_000,
  recv_timeout: 30_000,
  hackney: [
    pool: :test_pool,
    max_connections: 10
  ]

# Provider configuration for testing
config :runestone, :providers,
  openai: %{
    default_model: "gpt-4o-mini",
    timeout: 30_000,
    max_retries: 3,
    retry_delay: 1000
  },
  anthropic: %{
    default_model: "claude-3-sonnet",
    timeout: 30_000,
    max_retries: 3,
    retry_delay: 1000
  }

# Rate limiting configuration for testing
config :runestone, :rate_limiting,
  default_limits: %{
    requests_per_minute: 60,
    requests_per_hour: 1000,
    concurrent_requests: 10
  },
  cleanup_interval: 60_000,
  storage: :memory

# Authentication configuration for testing
config :runestone, :auth,
  key_store: :memory,
  session_timeout: 3600,
  rate_limit_cleanup: 300

# Circuit breaker configuration for testing
config :runestone, :circuit_breaker,
  failure_threshold: 5,
  recovery_time: 10_000,
  timeout: 5000

# Telemetry configuration for testing
config :runestone, :telemetry,
  enabled: true,
  handlers: [],
  metrics: [
    :request_duration,
    :request_count,
    :error_count,
    :rate_limit_blocks
  ]

# Overflow/queueing configuration for testing
config :runestone, :overflow,
  max_queue_size: 1000,
  processor_count: 2,
  retry_attempts: 3,
  storage: :memory

# Test database configuration (if needed)
config :runestone, Runestone.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "runestone_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Logger configuration for testing
config :logger,
  level: :warn,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :warn]
  ]

# ExUnit configuration
config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 5_000,
  refute_receive_timeout: 100

# Test-specific environment variables
System.put_env("MIX_ENV", "test")
System.put_env("RUNESTONE_ENV", "test")

# Mock external service URLs for testing
System.put_env("OPENAI_BASE_URL", "https://api.openai.com/v1")
System.put_env("ANTHROPIC_BASE_URL", "https://api.anthropic.com")

# Test API keys (these are fake keys for testing)
System.put_env("OPENAI_API_KEY", "sk-test-openai-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower))
System.put_env("ANTHROPIC_API_KEY", "sk-ant-test-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower))

# Router policy for testing
System.put_env("RUNESTONE_ROUTER_POLICY", "default")