defmodule Runestone.GraphQL.Types.Subscription do
  @moduledoc """
  GraphQL subscription types for real-time updates.
  """
  
  use Absinthe.Schema.Notation
  
  # Subscription types are defined in the main schema
  # This module can be used for subscription-specific helper types
  
  object :subscription_status do
    field :connected, non_null(:boolean)
    field :subscription_id, non_null(:string)
    field :topic, non_null(:string)
    field :created_at, non_null(:datetime)
  end
  
  object :subscription_error do
    field :code, non_null(:string)
    field :message, non_null(:string)
    field :details, :json
  end
end