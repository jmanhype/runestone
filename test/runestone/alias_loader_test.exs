defmodule Runestone.AliasLoaderTest do
  use ExUnit.Case, async: true
  alias Runestone.AliasLoader

  setup do
    # Ensure AliasLoader is started
    case Process.whereis(AliasLoader) do
      nil -> {:ok, _} = AliasLoader.start_link()
      pid when is_pid(pid) -> :ok
    end

    :ok
  end

  describe "resolve/1" do
    test "resolves known default aliases" do
      # These are default aliases that should be loaded
      assert {:ok, "groq:llama3-8b-8192"} = AliasLoader.resolve("fast")
      assert {:ok, "openai:gpt-4"} = AliasLoader.resolve("smart")
      assert {:ok, "anthropic:claude-3-haiku-20240307"} = AliasLoader.resolve("cheap")
    end

    test "returns :not_found for unknown aliases" do
      assert :not_found = AliasLoader.resolve("unknown_alias")
      assert :not_found = AliasLoader.resolve("does_not_exist")
    end
  end

  describe "list_aliases/0" do
    test "returns a map of all aliases" do
      aliases = AliasLoader.list_aliases()

      assert is_map(aliases)
      assert Map.has_key?(aliases, "fast")
      assert Map.has_key?(aliases, "smart")
      assert Map.has_key?(aliases, "cheap")
    end
  end

  describe "reload/0" do
    test "reloads aliases from configuration" do
      # Should not error
      assert :ok = AliasLoader.reload()
    end
  end
end