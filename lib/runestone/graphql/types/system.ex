defmodule Runestone.GraphQL.Types.System do
  @moduledoc """
  GraphQL types for system monitoring and management.
  """
  
  use Absinthe.Schema.Notation
  
  object :system_metrics do
    field :timestamp, non_null(:datetime)
    field :cpu, non_null(:cpu_metrics)
    field :memory, non_null(:memory_metrics)
    field :network, non_null(:network_metrics)
    field :disk, non_null(:disk_metrics)
    field :beam, non_null(:beam_metrics)
    field :ets, non_null(:ets_metrics)
    field :processes, non_null(:process_metrics)
  end
  
  object :cpu_metrics do
    field :usage_percent, non_null(:float)
    field :load_average, non_null(list_of(:float))
    field :cores, non_null(:integer)
    field :scheduler_usage, list_of(:float)
  end
  
  object :memory_metrics do
    field :total_mb, non_null(:float)
    field :used_mb, non_null(:float)
    field :free_mb, non_null(:float)
    field :beam_total_mb, non_null(:float)
    field :beam_processes_mb, non_null(:float)
    field :beam_ets_mb, non_null(:float)
    field :beam_binary_mb, non_null(:float)
  end
  
  object :network_metrics do
    field :bytes_sent, non_null(:integer)
    field :bytes_received, non_null(:integer)
    field :packets_sent, non_null(:integer)
    field :packets_received, non_null(:integer)
    field :errors, non_null(:integer)
    field :dropped, non_null(:integer)
  end
  
  object :disk_metrics do
    field :total_gb, non_null(:float)
    field :used_gb, non_null(:float)
    field :free_gb, non_null(:float)
    field :usage_percent, non_null(:float)
    field :io_read_mb_s, non_null(:float)
    field :io_write_mb_s, non_null(:float)
  end
  
  object :beam_metrics do
    field :uptime_seconds, non_null(:integer)
    field :run_queue, non_null(:integer)
    field :port_count, non_null(:integer)
    field :atom_count, non_null(:integer)
    field :module_count, non_null(:integer)
    field :reductions, non_null(:integer)
    field :gc_count, non_null(:integer)
    field :gc_words_reclaimed, non_null(:integer)
  end
  
  object :ets_metrics do
    field :table_count, non_null(:integer)
    field :total_memory_mb, non_null(:float)
    field :tables, list_of(:ets_table_info)
  end
  
  object :ets_table_info do
    field :name, non_null(:string)
    field :size, non_null(:integer)
    field :memory_bytes, non_null(:integer)
    field :type, non_null(:string)
    field :owner, non_null(:string)
  end
  
  object :process_metrics do
    field :count, non_null(:integer)
    field :limit, non_null(:integer)
    field :top_memory, list_of(:process_info)
    field :top_reductions, list_of(:process_info)
    field :top_message_queue, list_of(:process_info)
  end
  
  object :process_info do
    field :pid, non_null(:string)
    field :name, :string
    field :memory_bytes, non_null(:integer)
    field :reductions, non_null(:integer)
    field :message_queue_len, non_null(:integer)
    field :current_function, :string
    field :status, non_null(:string)
  end
  
  object :cache_stats do
    field :size, non_null(:integer)
    field :memory_bytes, non_null(:integer)
    field :hit_count, non_null(:integer)
    field :miss_count, non_null(:integer)
    field :hit_rate, non_null(:float)
    field :eviction_count, non_null(:integer)
    field :avg_entry_size_bytes, non_null(:float)
    field :ttl_expirations, non_null(:integer)
    field :oldest_entry_age_seconds, :integer
    field :newest_entry_age_seconds, :integer
  end
  
  object :health_status do
    field :status, non_null(:overall_health_status)
    field :checks, non_null(list_of(:health_check))
    field :version, non_null(:string)
    field :uptime_seconds, non_null(:integer)
    field :timestamp, non_null(:datetime)
  end
  
  object :health_check do
    field :name, non_null(:string)
    field :status, non_null(:check_status)
    field :message, :string
    field :details, :json
    field :duration_ms, :float
  end
  
  object :cache_operation_result do
    field :success, non_null(:boolean)
    field :message, non_null(:string)
    field :entries_affected, :integer
    field :duration_ms, :float
  end
  
  # Input types
  
  input_object :cache_entry_input do
    field :key, non_null(:string)
    field :value, non_null(:json)
    field :ttl, :integer
  end
  
  # Enums
  
  enum :overall_health_status do
    value :healthy
    value :degraded
    value :critical
    value :unknown
  end
  
  enum :check_status do
    value :passing
    value :warning
    value :critical
    value :unknown
  end
end