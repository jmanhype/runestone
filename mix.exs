defmodule Runestone.MixProject do
  use Mix.Project

  def project do
    [
      app: :runestone,
      version: "0.6.1",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      # Elixir 1.17+ has improved type checking that fixes db_connection issues
      elixirc_options: []
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Runestone.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.7"},
      {:plug, "~> 1.16"},
      {:oban, "~> 2.18"},
      {:telemetry, "~> 1.3"},
      {:jason, "~> 1.4"},
      {:httpoison, "~> 2.2"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19"},
      {:absinthe, "~> 1.7"},
      {:absinthe_plug, "~> 1.5"},
      {:dataloader, "~> 2.0"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
