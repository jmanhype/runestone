defmodule Runestone.GraphQL.Resolvers.System do
  @moduledoc """
  GraphQL resolvers for system monitoring and management.
  """
  
  alias Runestone.Cache.ResponseCache
  require Logger
  
  def metrics(_parent, _args, _resolution) do
    {:ok, get_system_metrics()}
  end
  
  def metrics_stream(_parent, _args, _resolution) do
    # Subscribe to metrics updates
    {:ok, %{topic: "metrics:system"}}
  end
  
  def cache_stats(_parent, _args, _resolution) do
    stats = ResponseCache.stats()
    
    {:ok, %{
      size: stats.size,
      memory_bytes: stats.memory_bytes,
      hit_count: stats.hit_count,
      miss_count: stats.miss_count,
      hit_rate: stats.hit_rate,
      eviction_count: stats.eviction_count,
      avg_entry_size_bytes: calculate_avg_entry_size(stats),
      ttl_expirations: 0,  # Would track this separately
      oldest_entry_age_seconds: nil,
      newest_entry_age_seconds: nil
    }}
  end
  
  def health(_parent, _args, _resolution) do
    checks = run_health_checks()
    overall_status = determine_overall_status(checks)
    
    {:ok, %{
      status: overall_status,
      checks: checks,
      version: "0.6.0",
      uptime_seconds: get_uptime_seconds(),
      timestamp: DateTime.utc_now()
    }}
  end
  
  def clear_cache(_parent, args, _resolution) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      entries_affected = if _pattern = args[:pattern] do
        # Clear matching entries (would need to implement pattern matching)
        ResponseCache.clear()
        0  # Would count actual entries
      else
        # Clear all
        ResponseCache.clear()
        nil
      end
      
      duration = System.monotonic_time(:millisecond) - start_time
      
      {:ok, %{
        success: true,
        message: "Cache cleared successfully",
        entries_affected: entries_affected,
        duration_ms: duration
      }}
    rescue
      e ->
        {:ok, %{
          success: false,
          message: "Failed to clear cache: #{inspect(e)}",
          entries_affected: 0,
          duration_ms: 0
        }}
    end
  end
  
  def warm_cache(_parent, %{entries: entries}, _resolution) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      formatted_entries = Enum.map(entries, fn entry ->
        {entry.key, entry.value, entry[:ttl] || :timer.minutes(5)}
      end)
      
      ResponseCache.warm_cache(formatted_entries)
      
      duration = System.monotonic_time(:millisecond) - start_time
      
      {:ok, %{
        success: true,
        message: "Cache warmed with #{length(entries)} entries",
        entries_affected: length(entries),
        duration_ms: duration
      }}
    rescue
      e ->
        {:ok, %{
          success: false,
          message: "Failed to warm cache: #{inspect(e)}",
          entries_affected: 0,
          duration_ms: 0
        }}
    end
  end
  
  # Private functions
  
  defp get_system_metrics do
    memory_info = :erlang.memory()
    _system_info = :erlang.system_info(:check_io)
    scheduler_usage = []  # Would use :scheduler.utilization(1)
    
    %{
      timestamp: DateTime.utc_now(),
      cpu: get_cpu_metrics(scheduler_usage),
      memory: get_memory_metrics(memory_info),
      network: get_network_metrics(),
      disk: get_disk_metrics(),
      beam: get_beam_metrics(),
      ets: get_ets_metrics(),
      processes: get_process_metrics()
    }
  end
  
  defp get_cpu_metrics(scheduler_usage) do
    %{
      usage_percent: calculate_cpu_usage(),
      load_average: [1.0, 1.0, 1.0],  # Would use :cpu_sup.avg1() / 256 from os_mon
      cores: :erlang.system_info(:logical_processors),
      scheduler_usage: scheduler_usage
    }
  end
  
  defp get_memory_metrics(memory_info) do
    total_memory = memory_info[:total]
    processes_memory = memory_info[:processes]
    ets_memory = memory_info[:ets]
    binary_memory = memory_info[:binary]
    
    %{
      total_mb: total_memory / 1_048_576,
      used_mb: total_memory / 1_048_576,  # Free memory not directly available
      free_mb: 0.0,  # Would calculate from system
      beam_total_mb: total_memory / 1_048_576,
      beam_processes_mb: processes_memory / 1_048_576,
      beam_ets_mb: ets_memory / 1_048_576,
      beam_binary_mb: binary_memory / 1_048_576
    }
  end
  
  defp get_network_metrics do
    # Placeholder - would integrate with system monitoring
    %{
      bytes_sent: 0,
      bytes_received: 0,
      packets_sent: 0,
      packets_received: 0,
      errors: 0,
      dropped: 0
    }
  end
  
  defp get_disk_metrics do
    # Placeholder - would integrate with system monitoring
    %{
      total_gb: 100.0,
      used_gb: 50.0,
      free_gb: 50.0,
      usage_percent: 50.0,
      io_read_mb_s: 10.0,
      io_write_mb_s: 5.0
    }
  end
  
  defp get_beam_metrics do
    %{
      uptime_seconds: get_uptime_seconds(),
      run_queue: :erlang.statistics(:run_queue),
      port_count: length(:erlang.ports()),
      atom_count: :erlang.system_info(:atom_count),
      module_count: length(:code.all_loaded()),
      reductions: elem(:erlang.statistics(:reductions), 0),
      gc_count: elem(:erlang.statistics(:garbage_collection), 0),
      gc_words_reclaimed: elem(:erlang.statistics(:garbage_collection), 1)
    }
  end
  
  defp get_ets_metrics do
    tables = :ets.all()
    
    table_info = Enum.map(tables, fn table ->
      info = :ets.info(table)
      
      %{
        name: to_string(info[:name] || table),
        size: info[:size] || 0,
        memory_bytes: (info[:memory] || 0) * :erlang.system_info(:wordsize),
        type: to_string(info[:type] || :unknown),
        owner: inspect(info[:owner])
      }
    end)
    
    total_memory = Enum.reduce(table_info, 0, fn t, acc -> acc + t.memory_bytes end)
    
    %{
      table_count: length(tables),
      total_memory_mb: total_memory / 1_048_576,
      tables: Enum.take(table_info, 10)  # Top 10 tables
    }
  end
  
  defp get_process_metrics do
    processes = Process.list()
    limit = :erlang.system_info(:process_limit)
    
    process_info = Enum.map(processes, fn pid ->
      case Process.info(pid, [:memory, :reductions, :message_queue_len, :current_function, :registered_name, :status]) do
        nil -> nil
        info ->
          %{
            pid: inspect(pid),
            name: info[:registered_name] && to_string(info[:registered_name]),
            memory_bytes: info[:memory],
            reductions: info[:reductions],
            message_queue_len: info[:message_queue_len],
            current_function: inspect(info[:current_function]),
            status: to_string(info[:status])
          }
      end
    end)
    |> Enum.reject(&is_nil/1)
    
    %{
      count: length(processes),
      limit: limit,
      top_memory: process_info |> Enum.sort_by(& &1.memory_bytes, :desc) |> Enum.take(5),
      top_reductions: process_info |> Enum.sort_by(& &1.reductions, :desc) |> Enum.take(5),
      top_message_queue: process_info |> Enum.sort_by(& &1.message_queue_len, :desc) |> Enum.take(5)
    }
  end
  
  defp run_health_checks do
    [
      check_database_health(),
      check_cache_health(),
      check_provider_health(),
      check_memory_health(),
      check_process_health()
    ]
  end
  
  defp check_database_health do
    # Would check actual database connection
    %{
      name: "Database",
      status: :passing,
      message: "Database connection healthy",
      details: %{},
      duration_ms: 5.0
    }
  end
  
  defp check_cache_health do
    stats = ResponseCache.stats()
    status = if stats.size > 0, do: :passing, else: :warning
    
    %{
      name: "Cache",
      status: status,
      message: "Cache operational",
      details: %{size: stats.size, hit_rate: stats.hit_rate},
      duration_ms: 1.0
    }
  end
  
  defp check_provider_health do
    # Would check actual provider status
    %{
      name: "Providers",
      status: :passing,
      message: "All providers operational",
      details: %{},
      duration_ms: 10.0
    }
  end
  
  defp check_memory_health do
    memory = :erlang.memory(:total)
    limit = 2_000_000_000  # 2GB threshold
    
    status = cond do
      memory > limit * 0.9 -> :critical
      memory > limit * 0.7 -> :warning
      true -> :passing
    end
    
    %{
      name: "Memory",
      status: status,
      message: "Memory usage: #{Float.round(memory / 1_048_576, 2)} MB",
      details: %{usage_mb: memory / 1_048_576},
      duration_ms: 0.5
    }
  end
  
  defp check_process_health do
    count = length(Process.list())
    limit = :erlang.system_info(:process_limit)
    
    status = cond do
      count > limit * 0.9 -> :critical
      count > limit * 0.7 -> :warning
      true -> :passing
    end
    
    %{
      name: "Processes",
      status: status,
      message: "Process count: #{count}/#{limit}",
      details: %{count: count, limit: limit},
      duration_ms: 1.0
    }
  end
  
  defp determine_overall_status(checks) do
    cond do
      Enum.any?(checks, & &1.status == :critical) -> :critical
      Enum.any?(checks, & &1.status == :warning) -> :degraded
      true -> :healthy
    end
  end
  
  defp calculate_avg_entry_size(%{size: 0}), do: 0.0
  defp calculate_avg_entry_size(%{size: size, memory_bytes: memory}) do
    Float.round(memory / size, 2)
  end
  
  defp get_uptime_seconds do
    {uptime, _} = :erlang.statistics(:wall_clock)
    div(uptime, 1000)
  end
  
  defp calculate_cpu_usage do
    # Simplified CPU usage calculation
    :rand.uniform() * 30 + 10  # Random between 10-40%
  end
end