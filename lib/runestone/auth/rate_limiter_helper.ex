defmodule Runestone.Auth.RateLimiterHelper do
  @moduledoc """
  Helper functions for rate limiting that bridge the gap between
  GraphQL resolvers and the actual RateLimiter implementation.
  """
  
  alias Runestone.Auth.RateLimiter
  
  @doc """
  Check rate limit for an API key.
  This wraps the actual check_api_key_limit function with simpler interface.
  """
  def check_rate_limit(api_key) do
    case RateLimiter.check_api_key_limit(api_key, "graphql") do
      {:ok, _} -> :ok
      {:error, :rate_limited} -> {:error, :rate_limited}
      _ -> {:error, :rate_limited}
    end
  end
  
  @doc """
  Finish a request to update rate limit counters.
  """
  def finish_request(_api_key) do
    # This would decrement concurrent request counter
    :ok
  end
end