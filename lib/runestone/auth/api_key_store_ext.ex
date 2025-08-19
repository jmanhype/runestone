defmodule Runestone.Auth.ApiKeyStoreExt do
  @moduledoc """
  Extended API key store functions for GraphQL operations.
  """
  
  alias Runestone.Auth.ApiKeyStore
  require Logger
  
  @doc """
  List all API keys in the store.
  """
  def list_keys do
    # This would normally query the GenServer state
    # For now, return empty list
    []
  end
  
  @doc """
  Store or update an API key.
  """
  def store_key(api_key, key_info) do
    # Use add_key for now
    ApiKeyStore.add_key(api_key, key_info)
  end
end