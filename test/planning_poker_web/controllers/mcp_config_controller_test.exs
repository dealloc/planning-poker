defmodule PlanningPokerWeb.McpConfigControllerTest do
  use PlanningPokerWeb.ConnCase

  test "GET /lobby/:id/mcp.json downloads MCP config", %{conn: conn} do
    conn = get(conn, ~p"/lobby/test-lobby/mcp.json")

    assert json_response(conn, 200) == %{
             "mcpServers" => %{
               "planning-poker-test-lobby" => %{
                 "type" => "http",
                 "url" => "http://www.example.com/mcp"
               }
             }
           }

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename=".mcp.json")
           ]
  end
end
