defmodule PlanningPokerWeb.PageControllerTest do
  use PlanningPokerWeb.ConnCase

  test "GET / renders the home live view", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Planning Poker"
  end
end
