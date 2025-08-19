defmodule RunestoneAnthropicExample do
  @moduledoc """
  Example of using Runestone with Anthropic's Claude API.
  This demonstrates real-world usage patterns.
  """
  
  alias Runestone.Pipeline.ProviderPool
  require Logger
  
  @doc """
  Simple chat completion with Claude
  """
  def chat_with_claude(message) do
    request = %{
      "messages" => [
        %{"role" => "user", "content" => message}
      ],
      "model" => "claude-3-sonnet-20240229",
      "max_tokens" => 1000,
      "temperature" => 0.7
    }
    
    provider_config = %{
      provider: "anthropic",
      api_key: System.get_env("ANTHROPIC_API_KEY"),
      timeout: 30_000
    }
    
    case ProviderPool.stream_request(provider_config, request) do
      {:ok, stream_ref} ->
        collect_stream_response(stream_ref)
      {:error, reason} ->
        Logger.error("Failed to chat with Claude: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Streaming chat with Claude
  """
  def stream_chat_with_claude(message, callback) do
    request = %{
      "messages" => [
        %{"role" => "user", "content" => message}
      ],
      "model" => "claude-3-sonnet-20240229",
      "max_tokens" => 2000,
      "stream" => true
    }
    
    provider_config = %{
      provider: "anthropic",
      api_key: System.get_env("ANTHROPIC_API_KEY")
    }
    
    # Start streaming
    case ProviderPool.stream_request(provider_config, request) do
      {:ok, stream_ref} ->
        handle_stream(stream_ref, callback)
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Use Claude for code analysis
  """
  def analyze_code(code_snippet, language \\ "elixir") do
    prompt = """
    Analyze the following #{language} code and provide:
    1. A brief summary of what it does
    2. Any potential issues or improvements
    3. Best practices recommendations
    
    Code:
    ```#{language}
    #{code_snippet}
    ```
    """
    
    chat_with_claude(prompt)
  end
  
  @doc """
  Use Claude for text summarization
  """
  def summarize_text(text, max_sentences \\ 3) do
    prompt = """
    Please summarize the following text in #{max_sentences} sentences:
    
    #{text}
    """
    
    chat_with_claude(prompt)
  end
  
  @doc """
  Multi-turn conversation with Claude
  """
  def conversation(messages) when is_list(messages) do
    request = %{
      "messages" => messages,
      "model" => "claude-3-opus-20240229",  # Use Opus for complex conversations
      "max_tokens" => 2000,
      "temperature" => 0.8
    }
    
    provider_config = %{
      provider: "anthropic",
      api_key: System.get_env("ANTHROPIC_API_KEY")
    }
    
    ProviderPool.stream_request(provider_config, request)
  end
  
  # Private functions
  
  defp collect_stream_response(stream_ref) do
    # Collect all chunks from the stream
    receive do
      {:stream_chunk, ^stream_ref, chunk} ->
        {:ok, chunk}
      {:stream_complete, ^stream_ref} ->
        {:ok, :complete}
      {:stream_error, ^stream_ref, error} ->
        {:error, error}
    after
      30_000 ->
        {:error, :timeout}
    end
  end
  
  defp handle_stream(stream_ref, callback) do
    receive do
      {:stream_chunk, ^stream_ref, chunk} ->
        callback.(chunk)
        handle_stream(stream_ref, callback)
      {:stream_complete, ^stream_ref} ->
        {:ok, :complete}
      {:stream_error, ^stream_ref, error} ->
        {:error, error}
    after
      30_000 ->
        {:error, :timeout}
    end
  end
end

# Example usage module
defmodule RunestoneAnthropicDemo do
  @moduledoc """
  Demonstration of Anthropic integration capabilities
  """
  
  def run_demo do
    IO.puts("\n🚀 Runestone + Anthropic Demo\n")
    
    # Example 1: Simple chat
    IO.puts("1️⃣ Simple Chat Example:")
    case RunestoneAnthropicExample.chat_with_claude("What is Elixir?") do
      {:ok, response} ->
        IO.puts("Claude says: #{inspect(response)}")
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    # Example 2: Code analysis
    IO.puts("\n2️⃣ Code Analysis Example:")
    code = """
    def factorial(0), do: 1
    def factorial(n) when n > 0, do: n * factorial(n - 1)
    """
    
    case RunestoneAnthropicExample.analyze_code(code) do
      {:ok, analysis} ->
        IO.puts("Analysis: #{inspect(analysis)}")
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    # Example 3: Multi-turn conversation
    IO.puts("\n3️⃣ Conversation Example:")
    messages = [
      %{"role" => "user", "content" => "Hi Claude, I'm learning Elixir."},
      %{"role" => "assistant", "content" => "That's great! Elixir is a fantastic language. What aspects are you focusing on?"},
      %{"role" => "user", "content" => "I'm interested in building scalable web applications."}
    ]
    
    case RunestoneAnthropicExample.conversation(messages) do
      {:ok, response} ->
        IO.puts("Conversation response: #{inspect(response)}")
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    IO.puts("\n✅ Demo complete!")
  end
end