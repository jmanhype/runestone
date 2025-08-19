defmodule Runestone.Auth.ApiKeyStoreTest do
  use ExUnit.Case, async: true
  
  alias Runestone.Auth.ApiKeyStore
  
  describe "API key management" do
    setup do
      {:ok, pid} = start_supervised({ApiKeyStore, [mode: :memory, initial_keys: []]})
      %{store: pid}
    end
    
    test "adds and retrieves API keys" do
      api_key = "sk-test123456789abcdef"
      
      assert :ok = ApiKeyStore.add_key(api_key, %{name: "Test Key"})
      assert {:ok, key_info} = ApiKeyStore.get_key_info(api_key)
      
      assert key_info.name == "Test Key"
      assert key_info.active == true
      assert key_info.rate_limit
    end
    
    test "prevents duplicate API keys" do
      api_key = "sk-duplicate123456789"
      
      assert :ok = ApiKeyStore.add_key(api_key, %{name: "First"})
      assert {:error, :already_exists} = ApiKeyStore.add_key(api_key, %{name: "Second"})
    end
    
    test "deactivates API keys" do
      api_key = "sk-deactivate123456789"
      
      ApiKeyStore.add_key(api_key, %{name: "Test Key"})
      assert :ok = ApiKeyStore.deactivate_key(api_key)
      
      {:ok, key_info} = ApiKeyStore.get_key_info(api_key)
      assert key_info.active == false
    end
    
    test "returns not found for unknown keys" do
      assert {:error, :not_found} = ApiKeyStore.get_key_info("sk-unknown123456789")
    end
    
    test "lists all keys with masked values" do
      api_key1 = "sk-list1234567890abcdef"
      api_key2 = "sk-list2345678901bcdefg"
      
      ApiKeyStore.add_key(api_key1, %{name: "Key 1"})
      ApiKeyStore.add_key(api_key2, %{name: "Key 2"})
      
      keys = ApiKeyStore.list_keys()
      
      assert length(keys) == 2
      assert Enum.all?(keys, fn key -> String.contains?(key.key, "...") end)
      assert Enum.any?(keys, fn key -> key.name == "Key 1" end)
      assert Enum.any?(keys, fn key -> key.name == "Key 2" end)
    end
  end
  
  describe "rate limit configuration" do
    setup do
      {:ok, _pid} = start_supervised({ApiKeyStore, [mode: :memory, initial_keys: []]})
      :ok
    end
    
    test "uses default rate limits when not specified" do
      api_key = "sk-defaultlimits123456"
      
      ApiKeyStore.add_key(api_key, %{name: "Default Limits"})
      {:ok, key_info} = ApiKeyStore.get_key_info(api_key)
      
      assert key_info.rate_limit.requests_per_minute == 60
      assert key_info.rate_limit.requests_per_hour == 1000
      assert key_info.rate_limit.concurrent_requests == 10
    end
    
    test "uses custom rate limits when specified" do
      api_key = "sk-customlimits123456"
      custom_limits = %{
        requests_per_minute: 30,
        requests_per_hour: 500,
        concurrent_requests: 5
      }
      
      ApiKeyStore.add_key(api_key, %{
        name: "Custom Limits",
        rate_limit: custom_limits
      })
      
      {:ok, key_info} = ApiKeyStore.get_key_info(api_key)
      
      assert key_info.rate_limit.requests_per_minute == 30
      assert key_info.rate_limit.requests_per_hour == 500
      assert key_info.rate_limit.concurrent_requests == 5
    end
  end
  
  describe "initial keys loading" do
    test "loads initial keys from configuration" do
      initial_keys = [
        {"sk-initial123456789", %{name: "Initial Key 1"}},
        {"sk-initial987654321", %{name: "Initial Key 2"}}
      ]
      
      {:ok, _pid} = start_supervised({ApiKeyStore, [
        mode: :memory,
        initial_keys: initial_keys
      ]})
      
      {:ok, key_info1} = ApiKeyStore.get_key_info("sk-initial123456789")
      {:ok, key_info2} = ApiKeyStore.get_key_info("sk-initial987654321")
      
      assert key_info1.name == "Initial Key 1"
      assert key_info2.name == "Initial Key 2"
    end
  end
  
  describe "metadata handling" do
    setup do
      {:ok, _pid} = start_supervised({ApiKeyStore, [mode: :memory, initial_keys: []]})
      :ok
    end
    
    test "stores and retrieves metadata" do
      api_key = "sk-metadata123456789"
      metadata = %{
        environment: "test",
        team_id: "team_123",
        permissions: ["read", "write"]
      }
      
      ApiKeyStore.add_key(api_key, %{
        name: "Metadata Key",
        metadata: metadata
      })
      
      {:ok, key_info} = ApiKeyStore.get_key_info(api_key)
      
      assert key_info.metadata == metadata
    end
  end
end