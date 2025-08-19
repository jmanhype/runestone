defmodule Runestone.GraphQL.Middleware.ErrorHandler do
  @moduledoc """
  GraphQL middleware for consistent error handling.
  """
  
  @behaviour Absinthe.Middleware
  
  def call(resolution, _config) do
    %{resolution | errors: Enum.flat_map(resolution.errors, &handle_error/1)}
  end
  
  defp handle_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
  end
  
  defp handle_error(error) do
    [format_error(error)]
  end
  
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error) when is_atom(error), do: to_string(error)
  defp format_error(error), do: inspect(error)
end