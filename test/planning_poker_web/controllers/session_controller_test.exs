defmodule PlanningPokerWeb.SessionControllerTest do
  use PlanningPokerWeb.ConnCase

  alias PlanningPoker.LobbyServer

  defp create_lobby(conn, params) do
    base = %{
      "action_type" => "create",
      "user_name" => "Host",
      "lobby_name" => "Sprint Planning",
      "planning_system" => "fibonacci"
    }

    conn =
      conn
      |> put_private(:plug_skip_csrf_protection, true)
      |> post(~p"/session", Map.merge(base, params))
    path = redirected_to(conn)
    "/lobby/" <> lobby_id = path
    {:ok, lobby} = LobbyServer.get(lobby_id)
    lobby
  end

  test "create stores the discussion threshold in minutes as seconds", %{conn: conn} do
    lobby = create_lobby(conn, %{"discussion_threshold" => "5"})
    assert lobby.discussion_threshold_seconds == 300
  end

  test "create leaves the threshold unset when blank", %{conn: conn} do
    lobby = create_lobby(conn, %{"discussion_threshold" => ""})
    assert lobby.discussion_threshold_seconds == nil
  end

  test "create ignores non-positive or non-numeric thresholds", %{conn: conn} do
    assert create_lobby(conn, %{"discussion_threshold" => "0"}).discussion_threshold_seconds == nil

    assert create_lobby(conn, %{"discussion_threshold" => "-3"}).discussion_threshold_seconds ==
             nil

    assert create_lobby(conn, %{"discussion_threshold" => "abc"}).discussion_threshold_seconds ==
             nil
  end

  test "create without a threshold param defaults to unset", %{conn: conn} do
    lobby = create_lobby(conn, %{})
    assert lobby.discussion_threshold_seconds == nil
  end
end
