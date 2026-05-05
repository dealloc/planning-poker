defmodule PlanningPokerWeb.Router do
  use PlanningPokerWeb, :router

  # forward "/mcp", Anubis.Server.Transport.StreamableHTTP.Plug, server: PlanningPoker.MCP.Server

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :delete_legacy_preferences_cookie
    plug :fetch_live_flash
    plug :put_root_layout, html: {PlanningPokerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :mcp do
    plug :accepts, ["json"]
  end

  scope "/", PlanningPokerWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/lobby/:id", LobbyLive
    get "/lobby/:id/mcp.json", McpConfigController, :show
    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
  end

  scope "/mcp" do
    pipe_through :mcp
    forward "/", Anubis.Server.Transport.StreamableHTTP.Plug, server: PlanningPoker.MCP.Server
  end

  defp delete_legacy_preferences_cookie(conn, _opts) do
    Plug.Conn.delete_resp_cookie(conn, "_pp_prefs")
  end

  # Other scopes may use custom stacks.
  # scope "/api", PlanningPokerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:planning_poker, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PlanningPokerWeb.Telemetry
    end
  end
end
