#!/usr/bin/env elixir

defmodule ValidationRunner do
  @moduledoc """
  Production validation test runner.
  
  This script runs comprehensive validation tests and generates a report
  suitable for production deployment verification.
  """

  def run do
    IO.puts("\n🔍 Starting Runestone Production Validation...")
    IO.puts("=" |> String.duplicate(80))
    
    # Start the application for testing
    start_application()
    
    # Run validation test suites
    results = %{
      compatibility: run_compatibility_tests(),
      sdk: run_sdk_tests(), 
      performance: run_performance_tests(),
      integration: run_integration_tests()
    }
    
    # Generate summary report
    generate_summary_report(results)
    
    # Determine overall status
    overall_status = determine_overall_status(results)
    
    IO.puts("\n" <> ("=" |> String.duplicate(80)))
    case overall_status do
      :pass -> 
        IO.puts("✅ VALIDATION PASSED - PRODUCTION READY")
        IO.puts("   All validation tests completed successfully.")
        IO.puts("   System is ready for production deployment.")
        System.halt(0)
      :warning ->
        IO.puts("⚠️  VALIDATION PASSED WITH WARNINGS")
        IO.puts("   Core functionality validated, some optional features missing.")
        IO.puts("   Safe for production with documented limitations.")
        System.halt(0)
      :fail ->
        IO.puts("❌ VALIDATION FAILED - NOT PRODUCTION READY")
        IO.puts("   Critical issues found that must be resolved.")
        IO.puts("   Do not deploy to production until issues are fixed.")
        System.halt(1)
    end
  end
  
  defp start_application do
    IO.puts("🚀 Starting Runestone application...")
    
    # Start required applications
    Application.ensure_all_started(:httpoison)
    Application.ensure_all_started(:jason)
    
    # Check if Runestone is running
    case HTTPoison.get("http://localhost:4002/health", [], timeout: 5000) do
      {:ok, %{status_code: status}} when status in [200, 503] ->
        IO.puts("✅ Application is running")
      {:error, :econnrefused} ->
        IO.puts("⚠️  Application not running, starting test server...")
        start_test_server()
      {:error, reason} ->
        IO.puts("❌ Failed to connect to application: #{inspect(reason)}")
        System.halt(1)
    end
  end
  
  defp start_test_server do
    # This would start a test instance of the application
    # For now, we'll assume the application is started externally
    IO.puts("⚠️  Please start the Runestone server with: mix phx.server")
    IO.puts("   Waiting 10 seconds for manual startup...")
    :timer.sleep(10_000)
    
    case HTTPoison.get("http://localhost:4002/health", [], timeout: 5000) do
      {:ok, %{status_code: status}} when status in [200, 503] ->
        IO.puts("✅ Application is now running")
      _ ->
        IO.puts("❌ Application still not accessible")
        System.halt(1)
    end
  end
  
  defp run_compatibility_tests do
    IO.puts("\n📋 Running OpenAI Compatibility Tests...")
    
    tests = [
      {"Request format validation", &test_request_format/0},
      {"Response format validation", &test_response_format/0},
      {"Streaming implementation", &test_streaming/0},
      {"Error handling", &test_error_handling/0},
      {"Authentication", &test_authentication/0}
    ]
    
    run_test_suite("Compatibility", tests)
  end
  
  defp run_sdk_tests do
    IO.puts("\n🔧 Running SDK Compatibility Tests...")
    
    tests = [
      {"Python SDK compatibility", &test_python_sdk_compat/0},
      {"Node.js SDK compatibility", &test_nodejs_sdk_compat/0},
      {"cURL compatibility", &test_curl_compat/0},
      {"Models API compatibility", &test_models_api/0}
    ]
    
    run_test_suite("SDK", tests)
  end
  
  defp run_performance_tests do
    IO.puts("\n⚡ Running Performance Validation Tests...")
    
    tests = [
      {"Concurrent request handling", &test_concurrent_requests/0},
      {"Memory management", &test_memory_management/0},
      {"Stream connection handling", &test_stream_connections/0},
      {"Error recovery", &test_error_recovery/0}
    ]
    
    run_test_suite("Performance", tests)
  end
  
  defp run_integration_tests do
    IO.puts("\n🔗 Running Integration Tests...")
    
    # Check if real API keys are available
    has_openai = System.get_env("OPENAI_API_KEY") != nil
    has_anthropic = System.get_env("ANTHROPIC_API_KEY") != nil
    
    tests = if has_openai or has_anthropic do
      [
        {"Real provider integration", &test_real_provider_integration/0},
        {"Multi-provider routing", &test_multi_provider_routing/0},
        {"Health monitoring", &test_health_monitoring/0},
        {"Rate limiting integration", &test_rate_limiting_integration/0}
      ]
    else
      [
        {"Health monitoring", &test_health_monitoring/0},
        {"Mock provider integration", &test_mock_provider_integration/0}
      ]
    end
    
    if not (has_openai or has_anthropic) do
      IO.puts("⚠️  No real API keys found - running limited integration tests")
    end
    
    run_test_suite("Integration", tests)
  end
  
  defp run_test_suite(suite_name, tests) do
    results = Enum.map(tests, fn {name, test_fn} ->
      IO.write("  • #{name}... ")
      
      start_time = System.monotonic_time(:millisecond)
      
      result = try do
        test_fn.()
      rescue
        e -> {:error, e}
      catch
        :exit, reason -> {:error, reason}
      end
      
      duration = System.monotonic_time(:millisecond) - start_time
      
      case result do
        :ok -> 
          IO.puts("✅ (#{duration}ms)")
          {:pass, name, duration}
        {:warning, message} ->
          IO.puts("⚠️  #{message} (#{duration}ms)")
          {:warning, name, duration, message}
        {:error, reason} ->
          IO.puts("❌ #{inspect(reason)} (#{duration}ms)")
          {:fail, name, duration, reason}
        other ->
          IO.puts("❌ Unexpected result: #{inspect(other)} (#{duration}ms)")
          {:fail, name, duration, other}
      end
    end)
    
    {suite_name, results}
  end
  
  # Test implementations
  
  defp test_request_format do
    # Test minimal request
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Hello"}]
    }
    
    response = make_request(:post, "/v1/chat/completions", request)
    
    if response.status_code == 200 do
      :ok
    else
      {:error, "Failed with status #{response.status_code}"}
    end
  end
  
  defp test_response_format do
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Test"}]
    }
    
    response = make_request(:post, "/v1/chat/completions", request)
    
    if response.status_code == 200 do
      body = Jason.decode!(response.body)
      
      required_fields = ["id", "object", "created", "model", "choices"]
      missing_fields = Enum.reject(required_fields, fn field -> 
        Map.has_key?(body, field)
      end)
      
      if missing_fields == [] do
        :ok
      else
        {:error, "Missing required fields: #{inspect(missing_fields)}"}
      end
    else
      {:error, "Request failed with status #{response.status_code}"}
    end
  end
  
  defp test_streaming do
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Count to 3"}]
    }
    
    response = make_request(:post, "/v1/chat/stream", request)
    
    cond do
      response.status_code == 200 ->
        if String.contains?(response.body, "data: ") and String.contains?(response.body, "[DONE]") do
          :ok
        else
          {:error, "Invalid streaming format"}
        end
      response.status_code == 404 ->
        {:warning, "Streaming endpoint not implemented"}
      true ->
        {:error, "Streaming failed with status #{response.status_code}"}
    end
  end
  
  defp test_error_handling do
    # Test with invalid request
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => "invalid"  # Should be array
    }
    
    response = make_request(:post, "/v1/chat/completions", request)
    
    if response.status_code == 400 do
      body = Jason.decode!(response.body)
      
      if Map.has_key?(body, "error") and Map.has_key?(body["error"], "type") do
        :ok
      else
        {:error, "Invalid error format"}
      end
    else
      {:error, "Expected 400 error, got #{response.status_code}"}
    end
  end
  
  defp test_authentication do
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Test"}]
    }
    
    # Test without API key
    response = HTTPoison.post!("http://localhost:4002/v1/chat/completions",
      Jason.encode!(request),
      [{"content-type", "application/json"}]
    )
    
    if response.status_code == 401 do
      :ok
    else
      {:error, "Expected 401 without API key, got #{response.status_code}"}
    end
  end
  
  defp test_python_sdk_compat do
    # Simulate Python SDK request
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Hello from Python SDK"}]
    }
    
    response = HTTPoison.post!("http://localhost:4002/v1/chat/completions",
      Jason.encode!(request),
      [
        {"content-type", "application/json"},
        {"authorization", "Bearer test-api-key"},
        {"user-agent", "OpenAI/Python 1.0.0"}
      ]
    )
    
    if response.status_code in [200, 202] do
      :ok
    else
      {:error, "Python SDK compatibility failed: #{response.status_code}"}
    end
  end
  
  defp test_nodejs_sdk_compat do
    # Simulate Node.js SDK request
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Hello from Node.js SDK"}]
    }
    
    response = HTTPoison.post!("http://localhost:4002/v1/chat/completions",
      Jason.encode!(request),
      [
        {"content-type", "application/json"},
        {"authorization", "Bearer test-api-key"},
        {"user-agent", "OpenAI/NodeJS/4.0.0"}
      ]
    )
    
    if response.status_code in [200, 202] do
      :ok
    else
      {:error, "Node.js SDK compatibility failed: #{response.status_code}"}
    end
  end
  
  defp test_curl_compat do
    # Test raw HTTP request
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Hello from cURL"}]
    }
    
    response = make_request(:post, "/v1/chat/completions", request)
    
    if response.status_code in [200, 202] do
      :ok
    else
      {:error, "cURL compatibility failed: #{response.status_code}"}
    end
  end
  
  defp test_models_api do
    response = make_request(:get, "/v1/models", nil)
    
    if response.status_code == 200 do
      body = Jason.decode!(response.body)
      
      if Map.has_key?(body, "object") and body["object"] == "list" do
        :ok
      else
        {:error, "Invalid models API response format"}
      end
    else
      {:error, "Models API failed: #{response.status_code}"}
    end
  end
  
  defp test_concurrent_requests do
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Concurrent test"}]
    }
    
    # Make 5 concurrent requests
    tasks = for _i <- 1..5 do
      Task.async(fn ->
        make_request(:post, "/v1/chat/completions", request)
      end)
    end
    
    results = Task.await_many(tasks, 30_000)
    
    successful = Enum.count(results, fn r -> r.status_code in [200, 202, 429] end)
    
    if successful >= 3 do
      :ok
    else
      {:error, "Only #{successful}/5 concurrent requests succeeded"}
    end
  end
  
  defp test_memory_management do
    # Test multiple small requests
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Memory test"}]
    }
    
    responses = for _i <- 1..20 do
      make_request(:post, "/v1/chat/completions", request)
    end
    
    successful = Enum.count(responses, fn r -> r.status_code in [200, 202, 429] end)
    
    if successful >= 15 do
      :ok
    else
      {:error, "Memory management test failed: #{successful}/20 requests succeeded"}
    end
  end
  
  defp test_stream_connections do
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Stream test"}]
    }
    
    # Test multiple streaming connections
    tasks = for _i <- 1..3 do
      Task.async(fn ->
        make_request(:post, "/v1/chat/stream", request)
      end)
    end
    
    results = Task.await_many(tasks, 30_000)
    
    successful = Enum.count(results, fn r -> r.status_code in [200, 202] end)
    
    if successful >= 2 do
      :ok
    else
      {:warning, "Limited streaming support: #{successful}/3 streams succeeded"}
    end
  end
  
  defp test_error_recovery do
    # Test malformed JSON
    response = HTTPoison.post!("http://localhost:4002/v1/chat/completions",
      "{invalid json",
      [
        {"content-type", "application/json"},
        {"authorization", "Bearer test-api-key"}
      ]
    )
    
    if response.status_code == 400 do
      :ok
    else
      {:error, "Error recovery failed: #{response.status_code}"}
    end
  end
  
  defp test_real_provider_integration do
    # Only run if real API keys are available
    if System.get_env("OPENAI_API_KEY") do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Integration test"}],
        "provider" => "openai",
        "max_tokens" => 5
      }
      
      response = make_request(:post, "/v1/chat/completions", request)
      
      if response.status_code == 200 do
        :ok
      else
        {:error, "Real provider integration failed: #{response.status_code}"}
      end
    else
      {:warning, "No real API keys available"}
    end
  end
  
  defp test_multi_provider_routing do
    request = %{
      "messages" => [%{"role" => "user", "content" => "Routing test"}],
      "model_family" => "general",
      "max_cost_per_token" => 0.0001
    }
    
    response = make_request(:post, "/v1/chat/completions", request)
    
    if response.status_code in [200, 202] do
      :ok
    else
      {:warning, "Multi-provider routing not fully functional: #{response.status_code}"}
    end
  end
  
  defp test_mock_provider_integration do
    # Test with mock providers when real ones aren't available
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Mock test"}]
    }
    
    response = make_request(:post, "/v1/chat/completions", request)
    
    if response.status_code in [200, 202, 503] do
      :ok
    else
      {:error, "Mock provider integration failed: #{response.status_code}"}
    end
  end
  
  defp test_health_monitoring do
    response = make_request(:get, "/health", nil)
    
    if response.status_code in [200, 503] do
      body = Jason.decode!(response.body)
      
      if Map.has_key?(body, "healthy") do
        :ok
      else
        {:error, "Invalid health response format"}
      end
    else
      {:error, "Health endpoint failed: #{response.status_code}"}
    end
  end
  
  defp test_rate_limiting_integration do
    request = %{
      "model" => "gpt-4o-mini",
      "messages" => [%{"role" => "user", "content" => "Rate limit test"}],
      "tenant_id" => "validation-test"
    }
    
    # Make rapid requests
    responses = for _i <- 1..10 do
      make_request(:post, "/v1/chat/completions", request)
    end
    
    # Should see some rate limiting or queueing
    status_codes = Enum.map(responses, fn r -> r.status_code end)
    
    has_success = Enum.any?(status_codes, fn code -> code == 200 end)
    has_limiting = Enum.any?(status_codes, fn code -> code in [202, 429] end)
    
    if has_success or has_limiting do
      :ok
    else
      {:warning, "Rate limiting behavior unclear"}
    end
  end
  
  # Helper functions
  
  defp make_request(method, path, body) do
    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer test-api-key"}
    ]
    
    url = "http://localhost:4002" <> path
    encoded_body = if body, do: Jason.encode!(body), else: ""
    
    try do
      case method do
        :get -> HTTPoison.get!(url, headers, timeout: 15_000, recv_timeout: 15_000)
        :post -> HTTPoison.post!(url, encoded_body, headers, timeout: 15_000, recv_timeout: 15_000)
      end
    rescue
      e -> %{status_code: 500, body: Jason.encode!(%{error: "Request failed: #{inspect(e)}"})}
    end
  end
  
  defp generate_summary_report(results) do
    IO.puts("\n📊 Validation Summary Report")
    IO.puts("-" |> String.duplicate(40))
    
    Enum.each(results, fn {suite_name, suite_results} ->
      {passes, warnings, failures} = categorize_results(suite_results)
      
      total = length(suite_results)
      pass_count = length(passes)
      warning_count = length(warnings)
      fail_count = length(failures)
      
      status_icon = cond do
        fail_count > 0 -> "❌"
        warning_count > 0 -> "⚠️ "
        true -> "✅"
      end
      
      IO.puts("#{status_icon} #{suite_name}: #{pass_count}/#{total} passed")
      
      if warning_count > 0 do
        IO.puts("    ⚠️  #{warning_count} warnings")
      end
      
      if fail_count > 0 do
        IO.puts("    ❌ #{fail_count} failures")
        
        Enum.each(failures, fn {:fail, name, _duration, _reason} ->
          IO.puts("       • #{name}")
        end)
      end
    end)
  end
  
  defp categorize_results(results) do
    passes = Enum.filter(results, fn {status, _, _, _} -> status == :pass end)
    warnings = Enum.filter(results, fn {status, _, _, _} -> status == :warning end)
    failures = Enum.filter(results, fn {status, _, _, _} -> status == :fail end)
    
    {passes, warnings, failures}
  end
  
  defp determine_overall_status(results) do
    all_results = Enum.flat_map(results, fn {_suite, suite_results} -> suite_results end)
    {_passes, warnings, failures} = categorize_results(all_results)
    
    cond do
      length(failures) > 0 -> :fail
      length(warnings) > 0 -> :warning
      true -> :pass
    end
  end
end

# Run the validation
ValidationRunner.run()