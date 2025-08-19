import Config

# Configure Ecto repos
config :runestone, ecto_repos: [Runestone.Repo]

# Import environment specific config
import_config "#{config_env()}.exs"