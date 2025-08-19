# ProviderPool and Enhanced Provider System Integration Design

## Overview

This document outlines the complete integration between the existing ProviderPool and the enhanced provider abstraction system. The integration removes hardcoded provider mappings, ensures proper stream handling, and maintains backward compatibility.

## Current State Analysis

### ProviderPool (Current)
- Located in `/lib/runestone/pipeline/provider_pool.ex`
- Handles stream request orchestration via supervised tasks
- Calls `Runestone.Providers.ProviderAdapter.stream_chat/2` 
- Still has hardcoded default model selection logic
- Missing provider configuration delegation to enhanced system

### Enhanced Provider System (Current)
- **ProviderAdapter**: Bridge between old and new interfaces
- **ProviderFactory**: Registry and management of provider instances
- **ProviderInterface**: Unified behavior for all providers
- **Provider Implementations**: OpenAI, Anthropic with full abstraction
- **Resilience Layer**: Circuit breakers, failover, retry logic

### ProviderRouter (Current)
- Routes requests to providers based on policy
- Returns hardcoded configuration structure
- Not integrated with enhanced provider system

## Integration Design

### Phase 1: Router Integration

**Goal**: Make ProviderRouter use the enhanced provider system for provider selection and configuration.

**Changes**:
1. Replace hardcoded provider mappings with ProviderFactory lookups
2. Use ProviderAdapter for health-based routing decisions
3. Maintain backward compatibility with existing API

### Phase 2: ProviderPool Enhancement

**Goal**: Remove all hardcoded provider logic from ProviderPool.

**Changes**:
1. Delegate model selection to ProviderAdapter
2. Remove hardcoded default model mappings
3. Use provider-specific configuration from ProviderFactory
4. Enhance error handling with provider abstraction

### Phase 3: Configuration Integration

**Goal**: Unify configuration management through the enhanced system.

**Changes**:
1. Provider configurations managed by ProviderFactory
2. Dynamic provider registration from application config
3. Health-based provider selection with automatic failover

## Implementation Plan

### 1. Enhanced ProviderRouter

Replace static routing with dynamic provider-aware routing that leverages the enhanced provider system for intelligent provider selection.

### 2. Updated ProviderPool

Remove hardcoded logic and delegate all provider-specific decisions to the ProviderAdapter, ensuring clean separation of concerns.

### 3. Configuration Bridge

Create configuration mapping that allows existing application configuration to work with the enhanced provider system.

### 4. Backward Compatibility Layer

Ensure existing API calls continue to work while transparently benefiting from enhanced features like failover, circuit breaking, and health monitoring.

## Benefits

1. **Dynamic Provider Management**: Add/remove providers without code changes
2. **Intelligent Routing**: Health-based and cost-aware provider selection
3. **Enhanced Reliability**: Automatic failover and circuit breaking
4. **Better Observability**: Comprehensive metrics and health monitoring
5. **Simplified Maintenance**: Centralized provider configuration and management

## Migration Strategy

1. **Zero-Downtime**: Changes maintain full backward compatibility
2. **Gradual Enhancement**: Existing functionality enhanced incrementally
3. **Configuration Migration**: Current provider configs automatically work
4. **Feature Opt-in**: New features available immediately but optional

## Quality Attributes

- **Reliability**: Enhanced with circuit breakers and failover
- **Maintainability**: Centralized provider management
- **Extensibility**: Easy to add new providers
- **Performance**: Optimized with connection pooling and caching
- **Observability**: Rich metrics and health monitoring