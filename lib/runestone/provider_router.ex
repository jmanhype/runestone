defmodule Runestone.ProviderRouter do
  @moduledoc """
  Routes requests to providers based on policy (default or cost-aware).
  Integrates with enhanced provider abstraction layer for intelligent routing.
  """
  
  alias Runestone.{Telemetry, CostTable}
  alias Runestone.Providers.{ProviderAdapter, ProviderFactory}
  require Logger
  
  def route(request) do
    policy = System.get_env("RUNESTONE_ROUTER_POLICY", "default")
    
    provider_config = 
      case policy do
        "cost" -> route_by_cost(request)
        "health" -> route_by_health(request)
        "enhanced" -> route_by_enhanced_system(request)
        _ -> route_default(request)
      end
    
    Telemetry.emit([:router, :decide], %{timestamp: System.system_time()}, %{
      provider: provider_config[:provider] || provider_config["provider"],
      policy: policy,
      request_id: request[:request_id] || request["request_id"],
      routing_strategy: get_routing_strategy(policy)
    })
    
    provider_config
  end
  
  defp route_default(request) do
    requested_provider = request["provider"] || request[:provider]
    requested_model = request["model"] || request[:model]
    
    # Use enhanced provider system for intelligent defaults
    case get_best_available_provider(requested_provider, requested_model) do
      {:ok, provider_info} ->
        %{
          provider: provider_info.name,
          model: provider_info.selected_model,
          config: provider_info.config,
          enhanced: true
        }
      
      {:error, _reason} ->
        # Fallback to legacy behavior for backward compatibility
        provider = requested_provider || "openai"
        model = requested_model || get_default_model(provider)
        
        %{
          provider: provider,
          model: model,
          config: get_provider_config(provider),
          enhanced: false,
          mock_mode: true  # Flag to indicate we're in mock mode
        }
    end
  end
  
  defp route_by_cost(request) do
    requirements = %{
      model_family: request["model_family"] || request[:model_family],
      capabilities: request["capabilities"] || request[:capabilities] || [],
      max_cost_per_token: request["max_cost_per_token"] || request[:max_cost_per_token]
    }
    
    # First try enhanced cost-aware routing
    case route_by_enhanced_cost(request, requirements) do
      {:ok, provider_config} -> provider_config
      {:error, _reason} ->
        # Fallback to legacy cost table
        case CostTable.get_cheapest(requirements) do
          nil -> route_default(request)
          provider_info -> provider_info
        end
    end
  end
  
  # New enhanced routing methods
  
  defp route_by_health(request) do
    case ProviderAdapter.get_provider_health() do
      %{status: :healthy, providers: providers} ->
        healthy_providers = 
          providers
          |> Enum.filter(fn {_name, health} -> health.healthy end)
          |> Enum.map(fn {name, _health} -> to_string(name) end)
        
        select_from_healthy_providers(request, healthy_providers)
      
      _ ->
        Logger.warning("No healthy providers available, falling back to default routing")
        route_default(request)
    end
  end
  
  defp route_by_enhanced_system(request) do
    # Use the enhanced provider system for full abstraction
    requested_model = request["model"] || request[:model]
    
    case ProviderFactory.list_providers() do
      [] ->
        Logger.warning("No providers registered in enhanced system, falling back")
        route_default(request)
      
      providers ->
        select_optimal_provider(request, providers, requested_model)
    end
  end
  
  defp route_by_enhanced_cost(request, requirements) do
    case ProviderFactory.estimate_costs(transform_request_for_cost_estimation(request)) do
      cost_map when map_size(cost_map) > 0 ->
        select_cheapest_available_provider(request, cost_map, requirements)
      
      _ ->
        {:error, :no_cost_estimates}
    end
  end
  
  # Helper functions for enhanced routing
  
  defp get_best_available_provider(requested_provider, requested_model) do
    cond do
      requested_provider && requested_model ->
        get_specific_provider_model(requested_provider, requested_model)
      
      requested_provider ->
        get_provider_with_default_model(requested_provider)
      
      requested_model ->
        get_any_provider_supporting_model(requested_model)
      
      true ->
        get_default_available_provider()
    end
  end
  
  defp get_specific_provider_model(provider_name, model) do
    case ProviderFactory.get_provider(provider_name) do
      {:ok, {module, config}} ->
        case validate_model_support(module, model) do
          :ok ->
            {:ok, %{
              name: provider_name,
              selected_model: model,
              config: config,
              module: module
            }}
          
          {:error, reason} ->
            {:error, {:model_not_supported, reason}}
        end
      
      {:error, reason} ->
        {:error, {:provider_not_found, reason}}
    end
  end
  
  defp get_provider_with_default_model(provider_name) do
    case ProviderFactory.get_provider(provider_name) do
      {:ok, {module, config}} ->
        provider_info = module.provider_info()
        default_model = List.first(provider_info.supported_models)
        
        {:ok, %{
          name: provider_name,
          selected_model: default_model,
          config: config,
          module: module
        }}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp get_any_provider_supporting_model(model) do
    case ProviderFactory.list_providers() do
      [] ->
        {:error, :no_providers_available}
      
      providers ->
        supporting_provider = 
          Enum.find(providers, fn provider ->
            case ProviderFactory.get_provider(provider.name) do
              {:ok, {module, _config}} ->
                provider_info = module.provider_info()
                model in provider_info.supported_models
              
              _ -> false
            end
          end)
        
        case supporting_provider do
          nil ->
            {:error, {:model_not_supported_by_any_provider, model}}
          
          provider ->
            case ProviderFactory.get_provider(provider.name) do
              {:ok, {module, config}} ->
                {:ok, %{
                  name: provider.name,
                  selected_model: model,
                  config: config,
                  module: module
                }}
              
              error ->
                error
            end
        end
    end
  end
  
  defp get_default_available_provider() do
    case ProviderFactory.list_providers() do
      [] ->
        {:error, :no_providers_available}
      
      [first_provider | _] ->
        get_provider_with_default_model(first_provider.name)
    end
  end
  
  defp select_from_healthy_providers(request, healthy_providers) do
    requested_provider = request["provider"] || request[:provider]
    
    target_provider = 
      if requested_provider && requested_provider in healthy_providers do
        requested_provider
      else
        List.first(healthy_providers)
      end
    
    case target_provider do
      nil -> route_default(request)
      provider -> route_to_specific_provider(request, provider)
    end
  end
  
  defp select_optimal_provider(request, providers, requested_model) do
    # Score providers based on health, capability, and preference
    scored_providers = 
      providers
      |> Enum.map(&score_provider(&1, request, requested_model))
      |> Enum.filter(fn {_provider, score} -> score > 0 end)
      |> Enum.sort_by(fn {_provider, score} -> score end, :desc)
    
    case scored_providers do
      [] -> route_default(request)
      [{best_provider, _score} | _] -> route_to_specific_provider(request, best_provider.name)
    end
  end
  
  defp select_cheapest_available_provider(request, cost_map, requirements) do
    valid_costs = 
      cost_map
      |> Enum.filter(fn {_provider, cost} -> cost != nil end)
      |> Enum.filter(fn {_provider, cost} ->
        max_cost = requirements[:max_cost_per_token]
        max_cost == nil || cost <= max_cost
      end)
      |> Enum.sort_by(fn {_provider, cost} -> cost end)
    
    case valid_costs do
      [] ->
        {:error, :no_cost_effective_providers}
      
      [{cheapest_provider, _cost} | _] ->
        {:ok, route_to_specific_provider(request, cheapest_provider)}
    end
  end
  
  defp route_to_specific_provider(request, provider_name) do
    requested_model = request["model"] || request[:model]
    
    case get_best_available_provider(provider_name, requested_model) do
      {:ok, provider_info} ->
        %{
          provider: provider_info.name,
          model: provider_info.selected_model,
          config: provider_info.config,
          enhanced: true
        }
      
      {:error, _reason} ->
        # Fallback to legacy for this specific provider
        model = requested_model || get_default_model(provider_name)
        %{
          provider: provider_name,
          model: model,
          config: get_provider_config(provider_name),
          enhanced: false
        }
    end
  end
  
  defp score_provider(provider, request, requested_model) do
    base_score = 100
    
    # Health score
    health_score = (provider.health_score || 1.0) * 50
    
    # Model support score
    model_score = 
      if requested_model do
        case ProviderFactory.get_provider(provider.name) do
          {:ok, {module, _config}} ->
            provider_info = module.provider_info()
            if requested_model in provider_info.supported_models, do: 30, else: 0
          
          _ -> 0
        end
      else
        20 # Bonus for any model support when no specific model requested
      end
    
    # Preference score (if explicitly requested)
    preference_score = 
      requested_provider = request["provider"] || request[:provider]
      if requested_provider && provider.name == requested_provider, do: 40, else: 0
    
    total_score = base_score + health_score + model_score + preference_score
    {provider, total_score}
  end
  
  defp validate_model_support(module, model) do
    provider_info = module.provider_info()
    if model in provider_info.supported_models do
      :ok
    else
      {:error, :model_not_supported}
    end
  end
  
  defp transform_request_for_cost_estimation(request) do
    # Convert legacy request format to enhanced format for cost estimation
    %{
      messages: request["messages"] || request[:messages] || [],
      model: request["model"] || request[:model],
      max_tokens: request["max_tokens"] || request[:max_tokens]
    }
  end
  
  defp get_routing_strategy(policy) do
    case policy do
      "cost" -> :cost_optimized
      "health" -> :health_aware
      "enhanced" -> :full_abstraction
      _ -> :legacy_compatible
    end
  end
  
  # Legacy fallback functions for backward compatibility
  
  defp get_default_model(provider) do
    # Try enhanced system first
    case ProviderFactory.get_provider(to_string(provider)) do
      {:ok, {module, _config}} ->
        provider_info = module.provider_info()
        List.first(provider_info.supported_models) || "gpt-4o-mini"
      
      _ ->
        # Fallback to application config
        config = Application.get_env(:runestone, :providers, %{})
        provider_config = Map.get(config, String.to_atom(provider), %{})
        Map.get(provider_config, :default_model, "gpt-4o-mini")
    end
  end
  
  defp get_provider_config(provider) do
    # Try enhanced system first
    case ProviderFactory.get_provider(to_string(provider)) do
      {:ok, {_module, config}} -> config
      _ ->
        # Fallback to application config
        config = Application.get_env(:runestone, :providers, %{})
        Map.get(config, String.to_atom(provider), %{})
    end
  end
end