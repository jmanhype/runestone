import Config

# Port configuration
config :runestone, :port, String.to_integer(System.get_env("PORT", "4003"))
config :runestone, :health_port, String.to_integer(System.get_env("HEALTH_PORT", "4004"))

# Provider configurations
config :runestone, :providers, %{
  openai: %{
    default_model: System.get_env("OPENAI_DEFAULT_MODEL", "gpt-4o-mini"),
    api_key_env: "OPENAI_API_KEY",
    base_url: System.get_env("OPENAI_BASE_URL", "https://api.openai.com/v1")
  },
  anthropic: %{
    default_model: System.get_env("ANTHROPIC_DEFAULT_MODEL", "claude-3-5-sonnet"),
    api_key_env: "ANTHROPIC_API_KEY",
    base_url: System.get_env("ANTHROPIC_BASE_URL", "https://api.anthropic.com/v1")
  }
}

# Cost table configuration
config :runestone, :cost_table, [
  %{
    provider: "openai",
    model: "gpt-4o-mini",
    model_family: "gpt-4",
    cost_per_1k_tokens: 0.15,
    capabilities: [:chat, :streaming, :function_calling],
    config: %{
      api_key_env: "OPENAI_API_KEY",
      base_url: "https://api.openai.com/v1"
    }
  },
  %{
    provider: "openai",
    model: "gpt-4o",
    model_family: "gpt-4",
    cost_per_1k_tokens: 2.50,
    capabilities: [:chat, :streaming, :function_calling, :vision],
    config: %{
      api_key_env: "OPENAI_API_KEY",
      base_url: "https://api.openai.com/v1"
    }
  },
  %{
    provider: "anthropic",
    model: "claude-3-5-sonnet",
    model_family: "claude",
    cost_per_1k_tokens: 3.00,
    capabilities: [:chat, :streaming, :function_calling, :vision],
    config: %{
      api_key_env: "ANTHROPIC_API_KEY",
      base_url: "https://api.anthropic.com/v1"
    }
  },
  %{
    provider: "anthropic",
    model: "claude-3-haiku",
    model_family: "claude",
    cost_per_1k_tokens: 0.25,
    capabilities: [:chat, :streaming],
    config: %{
      api_key_env: "ANTHROPIC_API_KEY",
      base_url: "https://api.anthropic.com/v1"
    }
  }
]

# Oban configuration with enhanced plugins
config :runestone, Oban,
  repo: Runestone.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 3600},
    {Oban.Plugins.Reindexer, schedule: "@daily"},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(60)},
    {Oban.Plugins.Cron,
      crontab: [
        {"0 * * * *", Runestone.Jobs.HealthCheck},
        {"*/5 * * * *", Runestone.Jobs.MetricsCollector}
      ]}
  ],
  queues: [
    overflow: [limit: 20, poll_interval: 1000],
    default: [limit: 10],
    priority: [limit: 50],
    metrics: [limit: 5]
  ],
  shutdown_grace_period: :timer.seconds(30),
  testing: :manual

# Database configuration (for Oban)
config :runestone, Runestone.Repo,
  database: System.get_env("DATABASE_NAME", "runestone_dev"),
  username: System.get_env("DATABASE_USER", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres"),
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

config :runestone, ecto_repos: [Runestone.Repo]

# Rate limiter config
config :runestone, :rate_limiter,
  max_concurrent_per_tenant: String.to_integer(System.get_env("MAX_CONCURRENT_PER_TENANT", "10"))

# Telemetry configuration
config :runestone, :telemetry,
  enabled: System.get_env("TELEMETRY_ENABLED", "true") == "true"

# Authentication configuration with test keys
config :runestone, :auth,
  storage_mode: :memory,
  initial_keys: [
    %{
      api_key: "sk-test-001",
      name: "Test Key 1",
      rate_limit: 100,
      concurrent_limit: 10
    },
    %{
      api_key: "sk-test-002", 
      name: "Test Key 2",
      rate_limit: 50,
      concurrent_limit: 5
    },
    %{
      api_key: "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",
      name: "User Anthropic Key",
      rate_limit: 100,
      concurrent_limit: 10,
      provider_keys: %{
        anthropic: "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"
      }
    }
  ]