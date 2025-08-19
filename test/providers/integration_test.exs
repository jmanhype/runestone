defmodule Runestone.Providers.IntegrationTest do
  use ExUnit.Case, async: false
  
  alias Runestone.Providers.{ProviderFactory, ProviderAdapter}

  setup_all do
    # Ensure the provider abstraction layer is running
    case start_supervised(Runestone.Providers.EnhancedProviderSupervisor) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
    
    :ok
  end

  describe "integration tests" do
    test "provider factory initializes successfully" do
      providers = ProviderFactory.list_providers()
      assert is_list(providers)
    end

    test "provider adapter handles missing providers gracefully" do
      request = %{
        model: "gpt-4o-mini",
        messages: [
          %{role: "user", content: "Hello, world!"}
        ]
      }

      events = []
      
      result = ProviderAdapter.stream_chat(request, fn event ->
        send(self(), {:event, event})
      end)

      # Should handle gracefully even without configured providers
      assert result in [:ok, {:error, :no_providers_available}, {:error, :service_not_configured}]
    end

    test "health monitoring works" do
      health = ProviderAdapter.get_provider_health()
      assert is_map(health)
      assert Map.has_key?(health, :status)
    end

    test "metrics collection works" do
      metrics = ProviderAdapter.get_provider_metrics()
      assert is_map(metrics)
    end
  end
end