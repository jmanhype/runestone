defmodule Runestone.GraphQL.Resolvers.Analytics do
  @moduledoc """
  GraphQL resolvers for analytics and usage tracking.
  """
  
  require Logger
  
  def usage(_parent, args, _resolution) do
    # Parse date range
    start_date = args[:start_date] || DateTime.add(DateTime.utc_now(), -7, :day)
    end_date = args[:end_date] || DateTime.utc_now()
    granularity = args[:granularity] || :hourly
    api_key = args[:api_key]
    
    # Generate analytics data
    analytics = %{
      period: %{
        start_date: start_date,
        end_date: end_date,
        granularity: granularity
      },
      data_points: generate_data_points(start_date, end_date, granularity, api_key),
      summary: generate_summary(start_date, end_date, api_key),
      providers: get_provider_usage(start_date, end_date, api_key),
      models: get_model_usage(start_date, end_date, api_key),
      top_users: get_top_users(start_date, end_date),
      cost_breakdown: get_cost_breakdown(start_date, end_date, api_key)
    }
    
    {:ok, analytics}
  end
  
  # Private functions
  
  defp generate_data_points(start_date, end_date, granularity, _api_key) do
    # Generate time series data points
    interval = case granularity do
      :minute -> 60
      :hourly -> 3600
      :daily -> 86400
      :weekly -> 604800
      :monthly -> 2592000
    end
    
    points = []
    current = start_date
    
    generate_points_recursive(current, end_date, interval, points)
  end
  
  defp generate_points_recursive(current, end_date, interval, acc) do
    if DateTime.compare(current, end_date) == :gt do
      Enum.reverse(acc)
    else
      point = %{
        timestamp: current,
        requests: :rand.uniform(1000),
        tokens: %{
          prompt_tokens: :rand.uniform(10000),
          completion_tokens: :rand.uniform(5000),
          total_tokens: :rand.uniform(15000)
        },
        latency: %{
          avg_ms: 100 + :rand.uniform(400),
          min_ms: 50 + :rand.uniform(50),
          max_ms: 500 + :rand.uniform(1500),
          p50_ms: 150 + :rand.uniform(100),
          p95_ms: 400 + :rand.uniform(600),
          p99_ms: 800 + :rand.uniform(1200)
        },
        errors: :rand.uniform(10),
        cache_hits: :rand.uniform(300),
        cost: :rand.uniform() * 100
      }
      
      next = DateTime.add(current, interval, :second)
      generate_points_recursive(next, end_date, interval, [point | acc])
    end
  end
  
  defp generate_summary(_start_date, _end_date, _api_key) do
    %{
      total_requests: 10000 + :rand.uniform(5000),
      successful_requests: 9500 + :rand.uniform(4500),
      failed_requests: 100 + :rand.uniform(400),
      total_tokens: 1000000 + :rand.uniform(500000),
      total_cost: 500.0 + :rand.uniform() * 1000,
      avg_latency_ms: 200.0 + :rand.uniform() * 100,
      cache_hit_rate: 0.3 + :rand.uniform() * 0.4,
      error_rate: 0.01 + :rand.uniform() * 0.04
    }
  end
  
  defp get_provider_usage(_start_date, _end_date, _api_key) do
    [
      %{
        provider: "OpenAI",
        requests: 5000 + :rand.uniform(2000),
        tokens: 500000 + :rand.uniform(200000),
        cost: 250.0 + :rand.uniform() * 500,
        avg_latency_ms: 180.0 + :rand.uniform() * 50,
        error_rate: 0.01
      },
      %{
        provider: "Anthropic",
        requests: 3000 + :rand.uniform(1500),
        tokens: 300000 + :rand.uniform(150000),
        cost: 150.0 + :rand.uniform() * 300,
        avg_latency_ms: 220.0 + :rand.uniform() * 80,
        error_rate: 0.02
      }
    ]
  end
  
  defp get_model_usage(_start_date, _end_date, _api_key) do
    [
      %{
        model: "gpt-4o",
        provider: "OpenAI",
        requests: 3000 + :rand.uniform(1000),
        tokens: %{
          prompt_tokens: 150000 + :rand.uniform(50000),
          completion_tokens: 75000 + :rand.uniform(25000),
          total_tokens: 225000 + :rand.uniform(75000)
        },
        cost: 200.0 + :rand.uniform() * 100,
        avg_latency_ms: 250.0 + :rand.uniform() * 50
      },
      %{
        model: "claude-3-opus",
        provider: "Anthropic",
        requests: 2000 + :rand.uniform(800),
        tokens: %{
          prompt_tokens: 100000 + :rand.uniform(40000),
          completion_tokens: 50000 + :rand.uniform(20000),
          total_tokens: 150000 + :rand.uniform(60000)
        },
        cost: 150.0 + :rand.uniform() * 75,
        avg_latency_ms: 300.0 + :rand.uniform() * 100
      }
    ]
  end
  
  defp get_top_users(_start_date, _end_date) do
    Enum.map(1..5, fn i ->
      %{
        api_key_id: "key_#{i}",
        api_key_name: "User #{i} API Key",
        requests: 1000 + :rand.uniform(500),
        tokens: 100000 + :rand.uniform(50000),
        cost: 50.0 + :rand.uniform() * 100,
        avg_latency_ms: 200.0 + :rand.uniform() * 50,
        last_request_at: DateTime.add(DateTime.utc_now(), -:rand.uniform(3600), :second)
      }
    end)
  end
  
  defp get_cost_breakdown(_start_date, _end_date, _api_key) do
    total = 1000.0
    
    %{
      by_provider: [
        %{label: "OpenAI", value: 600.0, percentage: 60.0, metadata: %{}},
        %{label: "Anthropic", value: 400.0, percentage: 40.0, metadata: %{}}
      ],
      by_model: [
        %{label: "gpt-4o", value: 400.0, percentage: 40.0, metadata: %{}},
        %{label: "claude-3-opus", value: 300.0, percentage: 30.0, metadata: %{}},
        %{label: "gpt-3.5-turbo", value: 200.0, percentage: 20.0, metadata: %{}},
        %{label: "claude-3-sonnet", value: 100.0, percentage: 10.0, metadata: %{}}
      ],
      by_api_key: [
        %{label: "Production", value: 700.0, percentage: 70.0, metadata: %{}},
        %{label: "Development", value: 200.0, percentage: 20.0, metadata: %{}},
        %{label: "Testing", value: 100.0, percentage: 10.0, metadata: %{}}
      ],
      by_day: generate_daily_costs(7),
      total: total
    }
  end
  
  defp generate_daily_costs(days) do
    Enum.map(0..(days - 1), fn i ->
      date = DateTime.add(DateTime.utc_now(), -i, :day)
      value = 100.0 + :rand.uniform() * 50
      
      %{
        label: Date.to_iso8601(DateTime.to_date(date)),
        value: value,
        percentage: value / 10.0,
        metadata: %{}
      }
    end)
  end
end