defmodule Runestone.GraphQL.Router do
  @moduledoc """
  GraphQL endpoint router using Absinthe.Plug.
  """
  
  use Plug.Router
  
  plug :match
  plug :dispatch
  
  forward "/graphql",
    to: Absinthe.Plug,
    init_opts: [
      schema: Runestone.GraphQL.Schema,
      json_codec: Jason
    ]
  
  forward "/graphiql",
    to: Absinthe.Plug.GraphiQL,
    init_opts: [
      schema: Runestone.GraphQL.Schema,
      interface: :playground,
      default_url: "/graphql"
    ]
  
  match _ do
    send_resp(conn, 404, "Not found")
  end
end