import Config

# Configure your database
config :runestone, Runestone.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "runestone_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Configure Oban for testing
config :runestone, Oban, testing: :inline