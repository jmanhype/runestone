defmodule Runestone.Pipeline.ProviderPoolExt do
  @moduledoc """
  Extended provider pool functions for GraphQL operations.
  """
  
  alias Runestone.Pipeline.ProviderPool
  require Logger
  
  @doc """
  Execute a request through the provider pool.
  """
  def execute_request(provider_config, request) do
    # Use stream_request since route_request doesn't exist
    case ProviderPool.stream_request(provider_config, request) do
      {:ok, request_id} -> {:ok, request_id}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :provider_error}
    end
  end
  
  @doc """
  Stream a request through the provider pool.
  """
  def stream_request(_provider_config, _request) do
    # Would set up streaming
    # For now, return mock task
    {:ok, %{pid: self()}}
  end
end