defmodule Runestone.GraphQL.Types.Chat do
  @moduledoc """
  GraphQL types for chat completions.
  """
  
  use Absinthe.Schema.Notation
  
  object :chat_completion do
    field :id, non_null(:string)
    field :model, non_null(:string)
    field :created, non_null(:integer)
    field :choices, non_null(list_of(:chat_choice))
    field :usage, :token_usage
    field :stream, non_null(:boolean)
    field :request_id, :string
    field :cached, non_null(:boolean)
    field :provider, :string
    field :latency_ms, :integer
  end
  
  object :chat_choice do
    field :index, non_null(:integer)
    field :message, non_null(:chat_message)
    field :finish_reason, :string
    field :logprobs, :json
  end
  
  object :chat_message do
    field :role, non_null(:message_role)
    field :content, :string
    field :name, :string
    field :function_call, :function_call
    field :tool_calls, list_of(:tool_call)
  end
  
  object :function_call do
    field :name, non_null(:string)
    field :arguments, non_null(:string)
  end
  
  object :tool_call do
    field :id, non_null(:string)
    field :type, non_null(:string)
    field :function, non_null(:function_call)
  end
  
  object :token_usage do
    field :prompt_tokens, non_null(:integer)
    field :completion_tokens, non_null(:integer)
    field :total_tokens, non_null(:integer)
    field :estimated_cost, :float
  end
  
  object :chat_stream_chunk do
    field :id, non_null(:string)
    field :choices, list_of(:stream_choice)
    field :created, non_null(:integer)
    field :model, non_null(:string)
    field :done, non_null(:boolean)
  end
  
  object :stream_choice do
    field :index, non_null(:integer)
    field :delta, :chat_message_delta
    field :finish_reason, :string
  end
  
  object :chat_message_delta do
    field :role, :message_role
    field :content, :string
    field :function_call, :function_call_delta
    field :tool_calls, list_of(:tool_call_delta)
  end
  
  object :function_call_delta do
    field :name, :string
    field :arguments, :string
  end
  
  object :tool_call_delta do
    field :index, :integer
    field :id, :string
    field :type, :string
    field :function, :function_call_delta
  end
  
  # Input types
  
  input_object :chat_completion_input do
    field :model, non_null(:string)
    field :messages, non_null(list_of(:chat_message_input))
    field :temperature, :float
    field :top_p, :float
    field :n, :integer
    field :stream, :boolean
    field :stop, list_of(:string)
    field :max_tokens, :integer
    field :presence_penalty, :float
    field :frequency_penalty, :float
    field :logit_bias, :json
    field :user, :string
    field :functions, list_of(:function_input)
    field :function_call, :string
    field :tools, list_of(:tool_input)
    field :tool_choice, :string
    field :response_format, :response_format_input
    field :seed, :integer
    field :api_key, non_null(:string)
    field :provider, :string
    field :cache_ttl, :integer
  end
  
  input_object :chat_message_input do
    field :role, non_null(:message_role)
    field :content, :string
    field :name, :string
    field :function_call, :function_call_input
    field :tool_calls, list_of(:tool_call_input)
  end
  
  input_object :function_call_input do
    field :name, non_null(:string)
    field :arguments, non_null(:string)
  end
  
  input_object :tool_call_input do
    field :id, non_null(:string)
    field :type, non_null(:string)
    field :function, non_null(:function_call_input)
  end
  
  input_object :function_input do
    field :name, non_null(:string)
    field :description, :string
    field :parameters, non_null(:json)
  end
  
  input_object :tool_input do
    field :type, non_null(:string)
    field :function, :function_input
  end
  
  input_object :response_format_input do
    field :type, non_null(:string)
    field :json_schema, :json
  end
  
  # Enums
  
  enum :message_role do
    value :system
    value :user
    value :assistant
    value :function
    value :tool
  end
  
  # JSON scalar is defined in Common types
end