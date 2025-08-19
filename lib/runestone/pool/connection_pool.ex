defmodule Runestone.Pool.ConnectionPool do
  @moduledoc """
  High-performance HTTP connection pooling with per-provider management.
  
  Features:
  - Connection reuse across requests
  - Per-provider pool isolation
  - Automatic health checking
  - Connection warmup
  - Circuit breaker integration
  - Pool metrics and monitoring
  """
  
  use GenServer
  require Logger
  
  @default_pool_size 50
  @default_max_overflow 10
  @default_timeout :timer.seconds(5)
  @health_check_interval :timer.seconds(30)
  
  defmodule PoolConfig do
    defstruct [
      :name,
      :size,
      :max_overflow,
      :timeout,
      :base_url,
      :headers,
      :ssl_options,
      :proxy,
      :health_check_path
    ]
  end
  
  defmodule ConnectionStats do
    defstruct [
      :active,
      :idle,
      :total,
      :requests_served,
      :avg_response_time,
      :errors,
      :last_error
    ]
  end
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Initialize a connection pool for a provider.
  """
  def create_pool(provider_name, config) do
    GenServer.call(__MODULE__, {:create_pool, provider_name, config})
  end
  
  @doc """
  Execute HTTP request using pooled connection.
  """
  def request(provider_name, method, path, body \\ nil, headers \\ [], opts \\ []) do
    with {:ok, pool_name} <- get_pool_name(provider_name),
         {:ok, conn} <- checkout_connection(pool_name, opts[:timeout] || @default_timeout) do
      
      start_time = System.monotonic_time(:millisecond)
      
      try do
        result = execute_request(conn, method, path, body, headers, opts)
        
        duration = System.monotonic_time(:millisecond) - start_time
        record_request_metrics(provider_name, duration, :success)
        
        result
      rescue
        error ->
          duration = System.monotonic_time(:millisecond) - start_time
          record_request_metrics(provider_name, duration, :error)
          reraise error, __STACKTRACE__
      after
        checkin_connection(pool_name, conn)
      end
    end
  end
  
  @doc """
  Execute multiple requests concurrently using the pool.
  """
  def batch_request(provider_name, requests, opts \\ []) do
    max_concurrency = opts[:max_concurrency] || 10
    timeout = opts[:timeout] || @default_timeout
    
    requests
    |> Task.async_stream(
      fn req ->
        request(
          provider_name,
          req.method,
          req.path,
          req.body,
          req.headers,
          [timeout: timeout]
        )
      end,
      max_concurrency: max_concurrency,
      timeout: timeout
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
    end)
  end
  
  @doc """
  Get pool statistics.
  """
  def stats(provider_name) do
    GenServer.call(__MODULE__, {:get_stats, provider_name})
  end
  
  @doc """
  Warm up connection pool by establishing connections.
  """
  def warmup(provider_name, count \\ nil) do
    GenServer.call(__MODULE__, {:warmup, provider_name, count})
  end
  
  @doc """
  Drain and close all connections for a provider.
  """
  def drain_pool(provider_name) do
    GenServer.call(__MODULE__, {:drain_pool, provider_name})
  end
  
  # GenServer callbacks
  
  @impl true
  def init(opts) do
    # Initialize Hackney pools for each provider
    base_config = %{
      timeout: opts[:timeout] || @default_timeout,
      max_connections: opts[:max_connections] || @default_pool_size
    }
    
    state = %{
      pools: %{},
      configs: %{},
      stats: %{},
      base_config: base_config
    }
    
    # Schedule periodic health checks
    schedule_health_check()
    
    Logger.info("Connection pool manager initialized")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:create_pool, provider_name, config}, _from, state) do
    pool_name = pool_name(provider_name)
    
    pool_config = %PoolConfig{
      name: pool_name,
      size: config[:pool_size] || @default_pool_size,
      max_overflow: config[:max_overflow] || @default_max_overflow,
      timeout: config[:timeout] || @default_timeout,
      base_url: config[:base_url],
      headers: config[:headers] || [],
      ssl_options: config[:ssl_options] || default_ssl_options(),
      proxy: config[:proxy],
      health_check_path: config[:health_check_path] || "/health"
    }
    
    # Create Hackney pool
    :ok = :hackney_pool.start_pool(pool_name, [
      timeout: pool_config.timeout,
      max_connections: pool_config.size,
      max_overflow: pool_config.max_overflow
    ])
    
    # Warm up connections
    warm_up_connections(pool_name, pool_config, min(5, pool_config.size))
    
    new_state = state
    |> put_in([:pools, provider_name], pool_name)
    |> put_in([:configs, provider_name], pool_config)
    |> put_in([:stats, provider_name], %ConnectionStats{
      active: 0,
      idle: pool_config.size,
      total: pool_config.size,
      requests_served: 0,
      avg_response_time: 0,
      errors: 0
    })
    
    Logger.info("Created connection pool for #{provider_name} with size #{pool_config.size}")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:get_stats, provider_name}, _from, state) do
    stats = get_in(state, [:stats, provider_name]) || %ConnectionStats{}
    
    # Get real-time stats from Hackney
    if pool_name = get_in(state, [:pools, provider_name]) do
      case :hackney_pool.get_stats(pool_name) do
        {:ok, hackney_stats} ->
          updated_stats = %{stats |
            active: hackney_stats[:in_use_count],
            idle: hackney_stats[:free_count],
            total: hackney_stats[:in_use_count] + hackney_stats[:free_count]
          }
          {:reply, {:ok, updated_stats}, state}
        
        _ ->
          {:reply, {:ok, stats}, state}
      end
    else
      {:reply, {:error, :pool_not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:warmup, provider_name, count}, _from, state) do
    if pool_config = get_in(state, [:configs, provider_name]) do
      pool_name = get_in(state, [:pools, provider_name])
      warm_count = count || min(10, pool_config.size)
      
      warm_up_connections(pool_name, pool_config, warm_count)
      {:reply, {:ok, warm_count}, state}
    else
      {:reply, {:error, :pool_not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:drain_pool, provider_name}, _from, state) do
    if pool_name = get_in(state, [:pools, provider_name]) do
      :hackney_pool.stop_pool(pool_name)
      
      new_state = state
      |> update_in([:pools], &Map.delete(&1, provider_name))
      |> update_in([:configs], &Map.delete(&1, provider_name))
      |> update_in([:stats], &Map.delete(&1, provider_name))
      
      Logger.info("Drained connection pool for #{provider_name}")
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :pool_not_found}, state}
    end
  end
  
  @impl true
  def handle_info(:health_check, state) do
    # Perform health checks on all pools
    Enum.each(state.configs, fn {provider_name, config} ->
      Task.start(fn ->
        perform_health_check(provider_name, config)
      end)
    end)
    
    schedule_health_check()
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:update_stats, provider_name, updates}, state) do
    new_state = update_in(state, [:stats, provider_name], fn stats ->
      Enum.reduce(updates, stats || %ConnectionStats{}, fn {key, value}, acc ->
        Map.put(acc, key, value)
      end)
    end)
    
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp pool_name(provider_name) do
    :"#{provider_name}_connection_pool"
  end
  
  defp get_pool_name(provider_name) do
    case GenServer.call(__MODULE__, {:get_pool, provider_name}) do
      {:ok, pool_name} -> {:ok, pool_name}
      _ -> {:error, :pool_not_found}
    end
  catch
    _ -> {:error, :pool_not_found}
  end
  
  defp checkout_connection(pool_name, timeout) do
    case :hackney_pool.checkout(pool_name, %{}, timeout) do
      {:ok, conn_ref} -> {:ok, conn_ref}
      {:error, reason} -> {:error, {:checkout_failed, reason}}
    end
  end
  
  defp checkin_connection(pool_name, conn) do
    :hackney_pool.checkin(pool_name, conn)
  end
  
  defp execute_request(conn, method, path, body, headers, opts) do
    url = build_url(opts[:base_url], path)
    
    hackney_opts = [
      {:pool, conn},
      {:recv_timeout, opts[:timeout] || @default_timeout},
      {:follow_redirect, true},
      {:max_redirect, 3}
    ]
    
    case :hackney.request(method, url, headers, body || "", hackney_opts) do
      {:ok, status, resp_headers, body_ref} ->
        {:ok, resp_body} = :hackney.body(body_ref)
        {:ok, %{status: status, headers: resp_headers, body: resp_body}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp warm_up_connections(pool_name, config, count) do
    # Establish connections proactively
    1..count
    |> Enum.map(fn _ ->
      Task.async(fn ->
        case checkout_connection(pool_name, 1000) do
          {:ok, conn} ->
            # Perform a lightweight request to establish connection
            if config.health_check_path do
              execute_request(
                conn,
                :head,
                config.health_check_path,
                nil,
                [],
                [base_url: config.base_url, timeout: 1000]
              )
            end
            checkin_connection(pool_name, conn)
          
          _ -> :ok
        end
      end)
    end)
    |> Enum.each(&Task.await(&1, 5000))
    
    Logger.debug("Warmed up #{count} connections for pool #{pool_name}")
  end
  
  defp perform_health_check(provider_name, config) do
    pool_name = pool_name(provider_name)
    
    case checkout_connection(pool_name, 1000) do
      {:ok, conn} ->
        health_result = execute_request(
          conn,
          :get,
          config.health_check_path,
          nil,
          [],
          [base_url: config.base_url, timeout: 2000]
        )
        
        checkin_connection(pool_name, conn)
        
        case health_result do
          {:ok, %{status: status}} when status in 200..299 ->
            Logger.debug("Health check passed for #{provider_name}")
            emit_telemetry(:health_check_pass, %{provider: provider_name})
          
          _ ->
            Logger.warning("Health check failed for #{provider_name}")
            emit_telemetry(:health_check_fail, %{provider: provider_name})
        end
      
      {:error, reason} ->
        Logger.error("Failed to check health for #{provider_name}: #{inspect(reason)}")
    end
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end
  
  defp build_url(base_url, path) do
    URI.merge(URI.parse(base_url || ""), path) |> to_string()
  end
  
  defp default_ssl_options do
    [
      {:versions, [:"tlsv1.2", :"tlsv1.3"]},
      {:verify, :verify_peer},
      {:cacerts, :certifi.cacerts()},
      {:depth, 3},
      {:customize_hostname_check, [
        {:match_fun, :public_key.pkix_verify_hostname_match_fun(:https)}
      ]}
    ]
  end
  
  defp record_request_metrics(provider_name, duration, status) do
    send(self(), {:update_stats, provider_name, [
      requests_served: 1,
      avg_response_time: duration
    ]})
    
    emit_telemetry(:request_complete, %{
      provider: provider_name,
      duration: duration,
      status: status
    })
  end
  
  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:runestone, :pool, event],
      %{timestamp: System.system_time()},
      metadata
    )
  end
end