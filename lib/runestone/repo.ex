defmodule Runestone.Repo do
  use Ecto.Repo,
    otp_app: :runestone,
    adapter: Ecto.Adapters.Postgres
end