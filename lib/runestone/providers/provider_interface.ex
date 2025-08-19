defmodule Runestone.Providers.ProviderInterface do
  @moduledoc """
  Enhanced provider behaviour that defines the contract for all AI provider implementations.
  
  This interface provides a unified abstraction layer for different AI providers,
  supporting streaming responses, authentication, error handling, and telemetry.
  """

  @type request :: %{
    required(:messages) => [message()],
    required(:model) => String.t(),
    optional(:temperature) => float(),
    optional(:max_tokens) => pos_integer(),
    optional(:stream) => boolean(),
    optional(atom()) => any()
  }

  @type message :: %{
    required(:role) => String.t(),
    required(:content) => String.t()
  }

  @type stream_event :: 
    {:delta_text, String.t()} |
    {:metadata, map()} |
    {:error, term()} |
    :done

  @type event_callback :: (stream_event() -> any())

  @type provider_config :: %{
    api_key: String.t(),
    base_url: String.t(),
    timeout: pos_integer(),
    retry_attempts: pos_integer(),
    circuit_breaker: boolean(),
    telemetry: boolean()
  }

  @type provider_info :: %{
    name: String.t(),
    version: String.t(),
    supported_models: [String.t()],
    capabilities: [atom()],
    rate_limits: map()
  }

  @doc """
  Stream a chat completion request to the provider.
  
  ## Parameters
  - `request`: The chat completion request
  - `on_event`: Callback function to handle streaming events
  - `config`: Provider-specific configuration
  
  ## Returns
  - `:ok` on successful completion
  - `{:error, reason}` on failure
  """
  @callback stream_chat(request(), event_callback(), provider_config()) :: 
    :ok | {:error, term()}

  @doc """
  Get provider information including supported models and capabilities.
  """
  @callback provider_info() :: provider_info()

  @doc """
  Validate provider configuration and connectivity.
  """
  @callback validate_config(provider_config()) :: :ok | {:error, term()}

  @doc """
  Transform a request to the provider's specific format.
  """
  @callback transform_request(request()) :: map()

  @doc """
  Parse and transform provider-specific error responses.
  """
  @callback handle_error(term()) :: {:error, term()}

  @doc """
  Get provider-specific authentication headers.
  """
  @callback auth_headers(provider_config()) :: [{String.t(), String.t()}]

  @doc """
  Calculate estimated cost for a request.
  """
  @callback estimate_cost(request()) :: {:ok, float()} | {:error, term()}

  @optional_callbacks [
    validate_config: 1,
    transform_request: 1,
    handle_error: 1,
    auth_headers: 1,
    estimate_cost: 1
  ]
end