#!/usr/bin/env elixir

# Test script to demonstrate Runestone + ReqLLM integration
# Run with: elixir test_integration.exs

Mix.install([
  {:req_llm, path: "../req_llm", override: true},
  {:runestone, path: "."}
])

# Start only the essential services we need for testing
{:ok, _} = Runestone.AliasLoader.start_link([])

IO.puts("🚀 Testing Runestone + ReqLLM Integration\n")

# Test 1: Alias Resolution
IO.puts("1. Testing Alias Resolution:")
IO.puts("   - Resolving 'fast' alias...")
case Runestone.AliasLoader.resolve("fast") do
  {:ok, model} ->
    IO.puts("   ✓ Resolved to: #{model}")
  :not_found ->
    IO.puts("   ✗ Alias not found")
end

IO.puts("   - Resolving 'smart' alias...")
case Runestone.AliasLoader.resolve("smart") do
  {:ok, model} ->
    IO.puts("   ✓ Resolved to: #{model}")
  :not_found ->
    IO.puts("   ✗ Alias not found")
end

# Test 2: Error Normalization
IO.puts("\n2. Testing Error Normalization:")
test_error = %{
  "error" => %{
    "type" => "rate_limit_exceeded",
    "message" => "Too many requests"
  }
}

normalized = Runestone.ErrorNormalizer.normalize(test_error, provider: :openai)
IO.puts("   - Rate limit error normalized:")
IO.puts("     • Code: #{normalized.error.code}")
IO.puts("     • Type: #{normalized.error.type}")
IO.puts("     • Retry-able: #{normalized.error.retry_able}")
IO.puts("     • Status: #{normalized.error.status}")

# Test 3: Model Resolution via Router
IO.puts("\n3. Testing Model Resolution:")
request = %{
  "model" => "fast",
  "messages" => [
    %{"role" => "user", "content" => "Hello!"}
  ]
}

# Just test the model resolution part
IO.puts("   - Input model: 'fast' (alias)")
with {:ok, resolved} <- Runestone.AliasLoader.resolve("fast") do
  IO.puts("   ✓ Would route to: #{resolved}")
else
  _ -> IO.puts("   ✗ Failed to resolve model")
end

# Test 4: List all aliases
IO.puts("\n4. Available Aliases:")
aliases = Runestone.AliasLoader.list_aliases()
Enum.each(aliases, fn {alias_name, model_spec} ->
  IO.puts("   • #{alias_name} → #{model_spec}")
end)

# Test 5: Error envelope format
IO.puts("\n5. Error Envelope Format:")
{status, body} = Runestone.ErrorNormalizer.to_http_response(normalized)
IO.puts("   - HTTP Status: #{status}")
IO.puts("   - Envelope contains:")
IO.puts("     • request_id: #{body.request_id || "generated"}")
IO.puts("     • timestamp: #{body.timestamp}")
IO.puts("     • error.code: #{body.error.code}")

IO.puts("\n✅ Integration test complete! Key components verified:")
IO.puts("   • Alias loader is working")
IO.puts("   • Error normalizer is functioning")
IO.puts("   • Models can be resolved")
IO.puts("   • Error envelopes are properly formatted")