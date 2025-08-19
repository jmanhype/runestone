ExUnit.start()

# Load test support modules
Code.require_file("support/test_helpers.exs", __DIR__)
Code.require_file("support/openai_test_config.exs", __DIR__)

# Configure ExUnit
ExUnit.configure([
  trace: false,
  capture_log: true,
  max_failures: :infinity,
  timeout: 60_000,  # 1 minute default timeout
  exclude: [:skip, :integration, :slow]
])

# Set up test environment
Application.ensure_all_started(:hackney)
Application.ensure_all_started(:jason)
Application.ensure_all_started(:plug)
Application.ensure_all_started(:telemetry)

# Configure logging for tests
Logger.configure(level: :warn)

# Configure application for testing
Application.put_env(:runestone, :environment, :test)

# Test-specific configuration
Application.put_env(:runestone, :providers, %{
  openai: %{
    default_model: "gpt-4o-mini",
    timeout: 30_000
  },
  anthropic: %{
    default_model: "claude-3-sonnet",
    timeout: 30_000
  }
})

# Global test setup
defmodule TestSetup do
  def setup_all do
    # Start required processes for testing
    Runestone.OpenAITestConfig.setup_test_environment()
    
    :ok
  end
  
  def teardown_all do
    # Clean up after all tests
    Runestone.OpenAITestConfig.cleanup_test_environment()
    
    :ok
  end
end

# Run global setup
TestSetup.setup_all()

# Schedule global teardown
System.at_exit(fn _exit_code ->
  TestSetup.teardown_all()
end)
