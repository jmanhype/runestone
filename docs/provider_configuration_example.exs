# Provider Configuration Example - Enhanced System Integration
#
# This file shows how the enhanced provider system integrates with existing
# application configuration while providing new capabilities.

import Config

# =============================================================================
# ENHANCED PROVIDER CONFIGURATION
# =============================================================================

# The enhanced provider system automatically migrates existing configuration
# and provides additional features like health monitoring, circuit breaking,
# and intelligent failover.

config :runestone, :providers, %{
  # OpenAI Configuration (automatically enhanced)
  openai: %{
    # Basic configuration (backward compatible)
    api_key: System.get_env("OPENAI_API_KEY"),
    base_url: "https://api.openai.com/v1",
    default_model: "gpt-4o-mini",
    
    # Enhanced features (new capabilities)
    timeout: 120_000,
    retry_attempts: 3,
    circuit_breaker: true,
    telemetry: true,
    health_check_interval: 30_000
  },
  
  # Anthropic Configuration (automatically enhanced)
  anthropic: %{
    api_key: System.get_env("ANTHROPIC_API_KEY"),
    base_url: "https://api.anthropic.com/v1",
    default_model: "claude-3-5-sonnet",
    
    # Enhanced features
    timeout: 120_000,
    retry_attempts: 3,
    circuit_breaker: true,
    telemetry: true,
    health_check_interval: 30_000
  },
  
  # Custom Provider Example (new capability)
  custom_openai: %{
    api_key: System.get_env("CUSTOM_OPENAI_API_KEY"),
    base_url: "https://custom-api.example.com/v1",
    default_model: "gpt-4o",
    timeout: 60_000,
    retry_attempts: 2,
    circuit_breaker: true,
    telemetry: true
  }
}

# =============================================================================
# ROUTING POLICIES
# =============================================================================

# Set the routing policy via environment variable:
# RUNESTONE_ROUTER_POLICY=default    # Legacy behavior with enhancements
# RUNESTONE_ROUTER_POLICY=health     # Health-aware routing
# RUNESTONE_ROUTER_POLICY=cost       # Cost-optimized routing
# RUNESTONE_ROUTER_POLICY=enhanced   # Full enhanced system features

# =============================================================================
# ENHANCED FEATURES CONFIGURATION
# =============================================================================

config :runestone, :enhanced_providers, %{
  # Failover configuration
  failover: %{
    default_strategy: :health_aware,
    max_attempts: 3,
    health_threshold: 0.7,
    rebalance_interval: 60_000
  },
  
  # Circuit breaker configuration
  circuit_breaker: %{
    failure_threshold: 5,
    recovery_timeout: 60_000,
    half_open_max_calls: 3
  },
  
  # Telemetry configuration
  telemetry: %{
    enabled: true,
    metrics_retention: 24 * 60 * 60, # 24 hours in seconds
    health_check_interval: 30_000
  },
  
  # Cost optimization
  cost_optimization: %{
    enabled: false,
    target_cost_reduction: 0.2, # 20% cost reduction target
    prefer_cheaper_models: true
  }
}

# =============================================================================
# BACKWARD COMPATIBILITY
# =============================================================================

# All existing configuration continues to work without changes.
# The enhanced system automatically:
# 1. Migrates existing provider configs to enhanced format
# 2. Adds default values for new features
# 3. Maintains API compatibility
# 4. Provides graceful fallbacks

# Example: Existing code continues to work unchanged
# ProviderRouter.route(%{"messages" => [...], "model" => "gpt-4o-mini"})
# ProviderPool.stream_request(provider_config, request)

# =============================================================================
# ENVIRONMENT VARIABLE OVERRIDES
# =============================================================================

# Environment variables take precedence over application config:
#
# Provider-specific settings:
# OPENAI_API_KEY=your_key
# OPENAI_BASE_URL=https://custom.openai.api/v1
# OPENAI_TIMEOUT=180000
# OPENAI_RETRY_ATTEMPTS=5
# OPENAI_CIRCUIT_BREAKER=true
#
# ANTHROPIC_API_KEY=your_key
# ANTHROPIC_BASE_URL=https://custom.anthropic.api/v1
# ANTHROPIC_TIMEOUT=180000
# ANTHROPIC_RETRY_ATTEMPTS=5
# ANTHROPIC_CIRCUIT_BREAKER=true
#
# Global settings:
# PROVIDER_TELEMETRY=true
# RUNESTONE_ROUTER_POLICY=enhanced

# =============================================================================
# MIGRATION NOTES
# =============================================================================

# When upgrading to the enhanced provider system:
# 1. No code changes required for basic functionality
# 2. Existing configurations are automatically migrated
# 3. New features are opt-in and configurable
# 4. Health monitoring and circuit breaking are enabled by default
# 5. Failover groups are created automatically for available providers

# =============================================================================
# MONITORING AND OBSERVABILITY
# =============================================================================

# The enhanced system provides comprehensive monitoring:
# - Provider health status
# - Circuit breaker states
# - Request/response metrics
# - Cost tracking
# - Failover events
# - Performance statistics

# Access monitoring data:
# ProviderAdapter.get_provider_health()
# ProviderAdapter.get_provider_metrics()
# ProviderFactory.health_check(:all)
# ProviderFactory.get_metrics(:all)