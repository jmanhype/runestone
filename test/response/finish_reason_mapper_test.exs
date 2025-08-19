defmodule Runestone.Response.FinishReasonMapperTest do
  use ExUnit.Case, async: true
  
  alias Runestone.Response.FinishReasonMapper
  
  describe "Anthropic finish reason mapping" do
    test "maps Anthropic stop reasons correctly" do
      assert FinishReasonMapper.map_anthropic_stop_reason("end_turn") == "stop"
      assert FinishReasonMapper.map_anthropic_stop_reason("max_tokens") == "length"
      assert FinishReasonMapper.map_anthropic_stop_reason("stop_sequence") == "stop"
      assert FinishReasonMapper.map_anthropic_stop_reason("tool_use") == "tool_calls"
      assert FinishReasonMapper.map_anthropic_stop_reason(nil) == nil
      assert FinishReasonMapper.map_anthropic_stop_reason("unknown_reason") == "stop"
    end
  end
  
  describe "OpenAI finish reason validation" do
    test "validates and passes through valid OpenAI reasons" do
      assert FinishReasonMapper.map_openai_finish_reason("stop") == "stop"
      assert FinishReasonMapper.map_openai_finish_reason("length") == "length"
      assert FinishReasonMapper.map_openai_finish_reason("tool_calls") == "tool_calls"
      assert FinishReasonMapper.map_openai_finish_reason("content_filter") == "content_filter"
      assert FinishReasonMapper.map_openai_finish_reason("function_call") == "function_call"
      assert FinishReasonMapper.map_openai_finish_reason(nil) == nil
    end
    
    test "defaults invalid OpenAI reasons to stop" do
      assert FinishReasonMapper.map_openai_finish_reason("invalid_reason") == "stop"
      assert FinishReasonMapper.map_openai_finish_reason("") == "stop"
    end
  end
  
  describe "generic provider finish reason mapping" do
    test "maps Anthropic provider reasons" do
      assert FinishReasonMapper.map_generic_finish_reason("anthropic", "end_turn") == "stop"
      assert FinishReasonMapper.map_generic_finish_reason("anthropic", "max_tokens") == "length"
      assert FinishReasonMapper.map_generic_finish_reason("anthropic", "tool_use") == "tool_calls"
    end
    
    test "maps OpenAI provider reasons" do
      assert FinishReasonMapper.map_generic_finish_reason("openai", "stop") == "stop"
      assert FinishReasonMapper.map_generic_finish_reason("openai", "length") == "length"
      assert FinishReasonMapper.map_generic_finish_reason("openai", "tool_calls") == "tool_calls"
    end
    
    test "maps Cohere provider reasons" do
      assert FinishReasonMapper.map_generic_finish_reason("cohere", "COMPLETE") == "stop"
      assert FinishReasonMapper.map_generic_finish_reason("cohere", "MAX_TOKENS") == "length"
      assert FinishReasonMapper.map_generic_finish_reason("cohere", "ERROR") == "stop"
    end
    
    test "maps Google/PaLM provider reasons" do
      assert FinishReasonMapper.map_generic_finish_reason("google", "STOP") == "stop"
      assert FinishReasonMapper.map_generic_finish_reason("google", "MAX_TOKENS") == "length"
      assert FinishReasonMapper.map_generic_finish_reason("google", "SAFETY") == "content_filter"
      assert FinishReasonMapper.map_generic_finish_reason("google", "RECITATION") == "content_filter"
    end
    
    test "maps Hugging Face provider reasons" do
      assert FinishReasonMapper.map_generic_finish_reason("huggingface", "eos_token") == "stop"
      assert FinishReasonMapper.map_generic_finish_reason("huggingface", "length") == "length"
      assert FinishReasonMapper.map_generic_finish_reason("huggingface", "stop_sequence") == "stop"
    end
    
    test "maps Azure provider reasons (same as OpenAI)" do
      assert FinishReasonMapper.map_generic_finish_reason("azure", "stop") == "stop"
      assert FinishReasonMapper.map_generic_finish_reason("azure", "length") == "length"
    end
    
    test "handles generic completion terms" do
      assert FinishReasonMapper.map_generic_finish_reason("custom", "completed") == "stop"
      assert FinishReasonMapper.map_generic_finish_reason("custom", "finished") == "stop"
      assert FinishReasonMapper.map_generic_finish_reason("custom", "done") == "stop"
      assert FinishReasonMapper.map_generic_finish_reason("custom", "stopped") == "stop"
    end
    
    test "handles generic length terms" do
      assert FinishReasonMapper.map_generic_finish_reason("custom", "max_length") == "length"
      assert FinishReasonMapper.map_generic_finish_reason("custom", "token_limit") == "length"
    end
    
    test "handles generic filter terms" do
      assert FinishReasonMapper.map_generic_finish_reason("custom", "filtered") == "content_filter"
    end
    
    test "defaults unknown reasons to stop" do
      assert FinishReasonMapper.map_generic_finish_reason("unknown", "weird_reason") == "stop"
      assert FinishReasonMapper.map_generic_finish_reason("provider", nil) == nil
    end
  end
  
  describe "finish reason analysis" do
    test "identifies successful completions" do
      assert FinishReasonMapper.is_successful_completion?("stop") == true
      assert FinishReasonMapper.is_successful_completion?("length") == true
      assert FinishReasonMapper.is_successful_completion?("tool_calls") == true
      assert FinishReasonMapper.is_successful_completion?("function_call") == true
      
      assert FinishReasonMapper.is_successful_completion?("content_filter") == false
      assert FinishReasonMapper.is_successful_completion?("error") == false
      assert FinishReasonMapper.is_successful_completion?(nil) == false
    end
    
    test "identifies truncated responses" do
      assert FinishReasonMapper.is_truncated?("length") == true
      
      assert FinishReasonMapper.is_truncated?("stop") == false
      assert FinishReasonMapper.is_truncated?("tool_calls") == false
      assert FinishReasonMapper.is_truncated?("content_filter") == false
    end
    
    test "identifies filtered responses" do
      assert FinishReasonMapper.is_filtered?("content_filter") == true
      
      assert FinishReasonMapper.is_filtered?("stop") == false
      assert FinishReasonMapper.is_filtered?("length") == false
      assert FinishReasonMapper.is_filtered?("tool_calls") == false
    end
  end
  
  describe "finish reason descriptions" do
    test "provides human-readable descriptions" do
      assert FinishReasonMapper.describe_finish_reason("stop") =~ "natural stopping point"
      assert FinishReasonMapper.describe_finish_reason("length") =~ "maximum token limit"
      assert FinishReasonMapper.describe_finish_reason("tool_calls") =~ "called a tool"
      assert FinishReasonMapper.describe_finish_reason("function_call") =~ "called a function"
      assert FinishReasonMapper.describe_finish_reason("content_filter") =~ "content policy"
      assert FinishReasonMapper.describe_finish_reason(nil) =~ "still in progress"
      assert FinishReasonMapper.describe_finish_reason("unknown") =~ "Unknown finish reason"
    end
  end
  
  describe "error to finish reason mapping" do
    test "maps error types to appropriate finish reasons" do
      # Rate limiting and authentication errors -> stop
      assert FinishReasonMapper.map_error_to_finish_reason(%{"type" => "rate_limit_error"}) == "stop"
      assert FinishReasonMapper.map_error_to_finish_reason(%{"type" => "authentication_error"}) == "stop"
      assert FinishReasonMapper.map_error_to_finish_reason(%{"type" => "permission_error"}) == "stop"
      assert FinishReasonMapper.map_error_to_finish_reason(%{"type" => "api_error"}) == "stop"
      
      # Content filtering -> content_filter
      assert FinishReasonMapper.map_error_to_finish_reason(%{"type" => "content_filter_error"}) == "content_filter"
      
      # Token limit errors -> length
      assert FinishReasonMapper.map_error_to_finish_reason(%{"code" => "context_length_exceeded"}) == "length"
      assert FinishReasonMapper.map_error_to_finish_reason(%{"code" => "max_tokens_exceeded"}) == "length"
      assert FinishReasonMapper.map_error_to_finish_reason(%{"code" => "token_limit_exceeded"}) == "length"
    end
    
    test "maps string errors based on content" do
      assert FinishReasonMapper.map_error_to_finish_reason("Token limit exceeded") == "length"
      assert FinishReasonMapper.map_error_to_finish_reason("Content filtered") == "content_filter"
      assert FinishReasonMapper.map_error_to_finish_reason("Unknown error") == "stop"
    end
    
    test "defaults unknown errors to stop" do
      assert FinishReasonMapper.map_error_to_finish_reason(%{"unknown" => "field"}) == "stop"
      assert FinishReasonMapper.map_error_to_finish_reason(nil) == "stop"
      assert FinishReasonMapper.map_error_to_finish_reason(123) == "stop"
    end
  end
  
  describe "finish reason validation" do
    test "validates correct finish reasons" do
      valid_reasons = ["stop", "length", "tool_calls", "function_call", "content_filter", nil]
      
      for reason <- valid_reasons do
        assert {:ok, ^reason} = FinishReasonMapper.validate_finish_reason(reason)
      end
    end
    
    test "rejects invalid finish reasons" do
      invalid_reasons = ["invalid", "unknown", "", 123, %{}, []]
      
      for reason <- invalid_reasons do
        assert {:error, _message} = FinishReasonMapper.validate_finish_reason(reason)
      end
    end
  end
  
  describe "streaming finish reason finalization" do
    test "uses definitive finish reason when available" do
      assert FinishReasonMapper.finalize_streaming_reason("stop", %{}) == "stop"
      assert FinishReasonMapper.finalize_streaming_reason("length", %{}) == "length"
      assert FinishReasonMapper.finalize_streaming_reason("tool_calls", %{}) == "tool_calls"
    end
    
    test "detects token limit from stream state" do
      stream_state = %{hit_token_limit: true}
      assert FinishReasonMapper.finalize_streaming_reason(nil, stream_state) == "length"
    end
    
    test "detects content filtering from stream state" do
      stream_state = %{content_filtered: true}
      assert FinishReasonMapper.finalize_streaming_reason(nil, stream_state) == "content_filter"
    end
    
    test "detects tool calls from stream state" do
      stream_state = %{tool_calls_made: true}
      assert FinishReasonMapper.finalize_streaming_reason(nil, stream_state) == "tool_calls"
    end
    
    test "defaults to stop for normal completion" do
      assert FinishReasonMapper.finalize_streaming_reason(nil, %{}) == "stop"
    end
    
    test "prioritizes definitive reason over stream state" do
      stream_state = %{hit_token_limit: true, content_filtered: true}
      assert FinishReasonMapper.finalize_streaming_reason("stop", stream_state) == "stop"
    end
  end
  
  describe "streaming state mapping" do
    test "maps Anthropic streaming states" do
      assert FinishReasonMapper.map_streaming_state("anthropic", %{"type" => "message_stop"}) == "stop"
      assert FinishReasonMapper.map_streaming_state("anthropic", %{"type" => "content_block_stop"}) == "stop"
      assert FinishReasonMapper.map_streaming_state("anthropic", %{"type" => "error"}) == "stop"
    end
    
    test "maps OpenAI streaming states" do
      assert FinishReasonMapper.map_streaming_state("openai", %{"finish_reason" => "stop"}) == "stop"
      assert FinishReasonMapper.map_streaming_state("openai", %{"finish_reason" => "length"}) == "length"
      assert FinishReasonMapper.map_streaming_state("openai", %{"finish_reason" => "tool_calls"}) == "tool_calls"
    end
    
    test "maps generic completion states" do
      assert FinishReasonMapper.map_streaming_state("custom", %{"done" => true}) == "stop"
      assert FinishReasonMapper.map_streaming_state("custom", %{"finished" => true}) == "stop"
      assert FinishReasonMapper.map_streaming_state("custom", %{"complete" => true}) == "stop"
    end
    
    test "returns nil for unknown states" do
      assert FinishReasonMapper.map_streaming_state("custom", %{"unknown" => "state"}) == nil
      assert FinishReasonMapper.map_streaming_state("provider", %{}) == nil
    end
  end
end