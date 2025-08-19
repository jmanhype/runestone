defmodule Runestone.GraphQL.Types.Common do
  @moduledoc """
  Common GraphQL scalar types and helpers.
  """
  
  use Absinthe.Schema.Notation
  
  # DateTime scalar
  scalar :datetime, name: "DateTime" do
    description "ISO8601 DateTime"
    
    serialize &DateTime.to_iso8601/1
    parse &parse_datetime/1
  end
  
  # JSON scalar (also defined in Chat but make it available globally)
  scalar :json, name: "JSON" do
    description "JSON scalar type"
    
    serialize &Jason.encode!/1
    parse &parse_json/1
  end
  
  # Private functions
  
  defp parse_datetime(%Absinthe.Blueprint.Input.String{value: value}) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> :error
    end
  end
  
  defp parse_datetime(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end
  
  defp parse_datetime(_) do
    :error
  end
  
  defp parse_json(%Absinthe.Blueprint.Input.String{value: value}) do
    case Jason.decode(value) do
      {:ok, result} -> {:ok, result}
      _ -> :error
    end
  end
  
  defp parse_json(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end
  
  defp parse_json(_) do
    :error
  end
end