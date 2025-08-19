defmodule Runestone.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation for fault tolerance.
  
  Provides protection against cascading failures by monitoring function calls
  and temporarily blocking calls to failing services.
  
  States:
  - :closed - Normal operation, requests pass through
  - :open - Service is failing, requests are blocked
  - :half_open - Testing if service has recovered
  """

  use GenServer
  require Logger

  @default_config %{
    failure_threshold: 5,      # Number of failures before opening
    success_threshold: 2,       # Number of successes in half_open before closing
    timeout: 60_000,           # Timeout for open state (ms)
    reset_timeout: 30_000,     # Time before moving from open to half_open (ms)
    window_size: 60_000        # Time window for failure counting (ms)
  }

  # Client API

  @doc """
  Execute a function through the circuit breaker.
  
  Returns:
  - {:ok, result} - Function executed successfully
  - {:error, :circuit_open} - Circuit is open, call blocked
  - {:error, reason} - Function failed with reason
  """
  def call(name, fun) when is_function(fun, 0) do
    breaker_name = get_breaker_name(name)
    
    case get_state(name) do
      :open ->
        {:error, :circuit_open}
      
      state when state in [:closed, :half_open] ->
        start_time = System.monotonic_time(:millisecond)
        
        try do
          result = fun.()
          duration = System.monotonic_time(:millisecond) - start_time
          record_success(breaker_name, duration)
          {:ok, result}
        rescue
          e ->
            duration = System.monotonic_time(:millisecond) - start_time
            record_failure(breaker_name, duration, e)
            {:error, Exception.message(e)}
        catch
          :exit, reason ->
            duration = System.monotonic_time(:millisecond) - start_time
            record_failure(breaker_name, duration, reason)
            {:error, reason}
        end
    end
  end

  @doc """
  Get the current state of a circuit breaker.
  
  Returns :closed, :open, or :half_open
  """
  def get_state(name) do
    breaker_name = get_breaker_name(name)
    
    case :ets.lookup(:circuit_breakers, breaker_name) do
      [{^breaker_name, state_data}] ->
        determine_current_state(state_data)
      [] ->
        # Initialize if doesn't exist
        init_breaker(breaker_name)
        :closed
    end
  end

  @doc """
  Reset a circuit breaker to closed state.
  """
  def reset(name) do
    breaker_name = get_breaker_name(name)
    
    state_data = %{
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      last_state_change: System.monotonic_time(:millisecond),
      config: @default_config
    }
    
    :ets.insert(:circuit_breakers, {breaker_name, state_data})
    Logger.info("Circuit breaker #{breaker_name} reset to closed state")
    :ok
  end

  @doc """
  Start the circuit breaker system.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for circuit breaker states (if it doesn't exist)
    case :ets.info(:circuit_breakers) do
      :undefined ->
        :ets.new(:circuit_breakers, [:set, :public, :named_table, read_concurrency: true])
      _ ->
        # Table already exists, that's fine
        :ok
    end
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_breakers()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private functions

  defp get_breaker_name(name) when is_binary(name), do: name
  defp get_breaker_name(name) when is_atom(name), do: Atom.to_string(name)
  defp get_breaker_name(name), do: inspect(name)

  defp init_breaker(name) do
    state_data = %{
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      last_state_change: System.monotonic_time(:millisecond),
      config: @default_config
    }
    
    :ets.insert(:circuit_breakers, {name, state_data})
  end

  defp determine_current_state(%{state: :open} = state_data) do
    current_time = System.monotonic_time(:millisecond)
    time_in_open = current_time - state_data.last_state_change
    
    if time_in_open >= state_data.config.reset_timeout do
      # Transition to half_open
      updated_state = %{state_data | 
        state: :half_open,
        success_count: 0,
        last_state_change: current_time
      }
      :ets.insert(:circuit_breakers, {get_breaker_name(state_data), updated_state})
      :half_open
    else
      :open
    end
  end

  defp determine_current_state(%{state: state}), do: state

  defp record_success(name, duration) do
    case :ets.lookup(:circuit_breakers, name) do
      [{^name, state_data}] ->
        current_state = determine_current_state(state_data)
        
        updated_state = case current_state do
          :half_open ->
            new_success_count = state_data.success_count + 1
            
            if new_success_count >= state_data.config.success_threshold do
              # Close the circuit
              Logger.info("Circuit breaker #{name} closing after successful recovery")
              %{state_data | 
                state: :closed,
                failure_count: 0,
                success_count: 0,
                last_state_change: System.monotonic_time(:millisecond)
              }
            else
              %{state_data | success_count: new_success_count}
            end
          
          :closed ->
            # Reset failure count on success in closed state
            %{state_data | failure_count: 0}
          
          _ ->
            state_data
        end
        
        :ets.insert(:circuit_breakers, {name, updated_state})
        emit_telemetry(name, :success, duration)
      
      [] ->
        init_breaker(name)
    end
  end

  defp record_failure(name, duration, reason) do
    case :ets.lookup(:circuit_breakers, name) do
      [{^name, state_data}] ->
        current_state = determine_current_state(state_data)
        current_time = System.monotonic_time(:millisecond)
        
        updated_state = case current_state do
          :half_open ->
            # Immediately open on failure in half_open
            Logger.warning("Circuit breaker #{name} reopening after failure in half_open state")
            %{state_data | 
              state: :open,
              failure_count: state_data.failure_count + 1,
              last_failure_time: current_time,
              last_state_change: current_time
            }
          
          :closed ->
            new_failure_count = state_data.failure_count + 1
            
            if new_failure_count >= state_data.config.failure_threshold do
              # Open the circuit
              Logger.warning("Circuit breaker #{name} opening after #{new_failure_count} failures")
              %{state_data | 
                state: :open,
                failure_count: new_failure_count,
                last_failure_time: current_time,
                last_state_change: current_time
              }
            else
              %{state_data | 
                failure_count: new_failure_count,
                last_failure_time: current_time
              }
            end
          
          :open ->
            # Already open, just update failure count
            %{state_data | 
              failure_count: state_data.failure_count + 1,
              last_failure_time: current_time
            }
        end
        
        :ets.insert(:circuit_breakers, {name, updated_state})
        emit_telemetry(name, :failure, duration, reason)
      
      [] ->
        init_breaker(name)
        record_failure(name, duration, reason)
    end
  end

  defp emit_telemetry(name, event, duration, reason \\ nil) do
    :telemetry.execute(
      [:circuit_breaker, event],
      %{duration: duration},
      %{
        breaker: name,
        reason: reason
      }
    )
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 60_000) # Every minute
  end

  defp cleanup_expired_breakers do
    current_time = System.monotonic_time(:millisecond)
    cutoff_time = current_time - 3600_000 # 1 hour
    
    :ets.select_delete(:circuit_breakers, [
      {
        {:"$1", %{last_state_change: :"$2"}},
        [{:<, :"$2", cutoff_time}],
        [true]
      }
    ])
  end
end