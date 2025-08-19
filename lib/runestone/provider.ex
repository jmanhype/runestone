defmodule Runestone.Provider do
  @moduledoc """
  Behaviour for provider plugins. Implementations should perform the HTTP/SSE
  work and invoke `on_event` with either `{:delta_text, binary}`, `:done`, or `{:error, term}`.
  """
  
  @callback stream_chat(request :: map(), on_event :: (term() -> any())) :: :ok | {:error, term()}
end