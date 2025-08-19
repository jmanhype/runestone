defmodule Runestone.Providers.Resilience.RetryPolicy do
  @moduledoc """
  Implements retry logic with exponential backoff for provider requests.
  
  Features:
  - Configurable retry attempts and delays
  - Exponential backoff with jitter
  - Circuit breaker integration
  - Retry-specific telemetry
  """

  require Logger
  alias Runestone.TelemetryEvents

  @type retry_config :: %{
    max_attempts: pos_integer(),
    base_delay_ms: pos_integer(),
    max_delay_ms: pos_integer(),
    backoff_factor: float(),
    jitter: boolean(),
    retryable_errors: [atom()]
  }

  @default_config %{
    max_attempts: 3,
    base_delay_ms: 1000,
    max_delay_ms: 30_000,
    backoff_factor: 2.0,
    jitter: true,
    retryable_errors: [:timeout, :connection_error, :rate_limit, :server_error]
  }

  @doc """
  Execute a function with retry logic.
  
  ## Parameters
  - `fun`: The function to execute
  - `config`: Retry configuration (optional, uses defaults if not provided)
  - `context`: Additional context for telemetry
  
  ## Returns
  - `{:ok, result}` on success
  - `{:error, reason}` after all retries exhausted
  """
  @spec with_retry(fun(), retry_config() | nil, map()) :: {:ok, any()} | {:error, term()}
  def with_retry(fun, config \\ nil, context \\ %{}) when is_function(fun, 0) do
    retry_config = merge_config(config)
    
    TelemetryEvents.emit([:retry, :start], %{
      max_attempts: retry_config.max_attempts,
      timestamp: System.system_time()
    }, context)

    do_retry(fun, retry_config, 1, nil, context)
  end

  defp do_retry(fun, config, attempt, last_error, context) do
    try do
      result = fun.()
      
      if attempt > 1 do
        TelemetryEvents.emit([:retry, :success], %{
          attempt: attempt,
          total_attempts: config.max_attempts,
          timestamp: System.system_time()
        }, context)
        
        Logger.info("Retry succeeded on attempt #{attempt}/#{config.max_attempts}")
      end
      
      {:ok, result}
    rescue
      error ->
        handle_retry_error(error, config, attempt, context)
    catch
      :exit, reason ->
        handle_retry_error(reason, config, attempt, context)
      :throw, reason ->
        handle_retry_error(reason, config, attempt, context)
    end
  end

  defp handle_retry_error(error, config, attempt, context) do
    if attempt >= config.max_attempts do
      TelemetryEvents.emit([:retry, :exhausted], %{
        final_attempt: attempt,
        total_attempts: config.max_attempts,
        final_error: error,
        timestamp: System.system_time()
      }, context)
      
      Logger.error("All retry attempts exhausted (#{attempt}/#{config.max_attempts}): #{inspect(error)}")
      {:error, error}
    else
      if retryable_error?(error, config.retryable_errors) do
        delay = calculate_delay(attempt, config)
        
        TelemetryEvents.emit([:retry, :attempt], %{
          attempt: attempt,
          total_attempts: config.max_attempts,
          delay_ms: delay,
          error: error,
          timestamp: System.system_time()
        }, context)
        
        Logger.warning("Retry attempt #{attempt}/#{config.max_attempts} failed: #{inspect(error)}, retrying in #{delay}ms")
        
        :timer.sleep(delay)
        do_retry(fn -> raise error end, config, attempt + 1, error, context)
      else
        TelemetryEvents.emit([:retry, :non_retryable], %{
          attempt: attempt,
          error: error,
          timestamp: System.system_time()
        }, context)
        
        Logger.error("Non-retryable error on attempt #{attempt}: #{inspect(error)}")
        {:error, error}
      end
    end
  end

  defp retryable_error?(error, retryable_errors) do
    case error do
      %{__struct__: struct} when struct in [HTTPoison.Error] ->
        :connection_error in retryable_errors
      
      {:timeout, _} ->
        :timeout in retryable_errors
      
      {:error, :timeout} ->
        :timeout in retryable_errors
      
      {:error, :econnrefused} ->
        :connection_error in retryable_errors
      
      {:error, :closed} ->
        :connection_error in retryable_errors
      
      {:error, "HTTP " <> code} ->
        case String.to_integer(code) do
          status when status >= 500 -> :server_error in retryable_errors
          429 -> :rate_limit in retryable_errors
          _ -> false
        end
      
      _ ->
        false
    end
  end

  defp calculate_delay(attempt, config) do
    base_delay = config.base_delay_ms * :math.pow(config.backoff_factor, attempt - 1)
    delay = min(base_delay, config.max_delay_ms)
    
    if config.jitter do
      jitter_amount = delay * 0.1
      delay + (:rand.uniform() - 0.5) * 2 * jitter_amount
    else
      delay
    end
    |> round()
  end

  defp merge_config(nil), do: @default_config
  defp merge_config(config), do: Map.merge(@default_config, config)
end