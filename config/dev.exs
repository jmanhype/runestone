import Config

# Configure your database
config :runestone, Runestone.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "runestone_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Configure Oban
config :runestone, Oban,
  repo: Runestone.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [overflow: 10]