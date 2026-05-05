defmodule PlanningPokerWeb.McpConfigController do
  use PlanningPokerWeb, :controller

  def show(conn, %{"id" => lobby_id}) do
    config = %{
      "mcpServers" => %{
        "planning-poker" => %{
          "type" => "http",
          "url" => url(~p"/mcp")
        }
      }
    }

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", ~s(attachment; filename=".mcp.json"))
    |> json(config)
  end
end
