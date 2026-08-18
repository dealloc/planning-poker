defmodule PlanningPoker.MCP.Tools.CreateLobbyTest do
  use ExUnit.Case, async: true

  alias Anubis.Server.Frame
  alias PlanningPoker.LobbyServer
  alias PlanningPoker.MCP.Tools.CreateLobby

  defp execute(params) do
    {:reply, response, _frame} = CreateLobby.execute(params, Frame.new())
    response
  end

  defp payload(response) do
    refute response.isError
    [%{"type" => "text", "text" => text}] = response.content
    JSON.decode!(text)
  end

  test "creates a lobby that can be looked up afterwards" do
    payload = execute(%{name: "Sprint 42"}) |> payload()

    assert {:ok, lobby} = LobbyServer.get(payload["id"])
    assert lobby.name == "Sprint 42"
    assert lobby.planning_system == :fibonacci
    assert payload["url"] =~ "/lobby/#{payload["id"]}"
  end

  test "defaults let members (and the agent) queue items" do
    payload = execute(%{name: "Sprint 42"}) |> payload()

    {:ok, lobby} = LobbyServer.get(payload["id"])
    assert lobby.members_can_add_to_queue
    refute lobby.auto_reveal
    assert lobby.creator_id == nil
  end

  test "honours the optional settings" do
    payload =
      execute(%{
        name: "Sprint 42",
        planning_system: "tshirt",
        auto_reveal: true,
        members_can_add_to_queue: false,
        discussion_threshold_minutes: 5
      })
      |> payload()

    {:ok, lobby} = LobbyServer.get(payload["id"])
    assert lobby.planning_system == :tshirt
    assert lobby.auto_reveal
    refute lobby.members_can_add_to_queue
    assert lobby.discussion_threshold_seconds == 300
    assert payload["cards"] == PlanningPoker.Lobby.cards(:tshirt)
  end

  test "creates a lobby with a custom deck" do
    payload =
      execute(%{
        name: "Sprint 42",
        planning_system: "custom",
        custom_cards: ["S", " M ", "", "L"]
      })
      |> payload()

    {:ok, lobby} = LobbyServer.get(payload["id"])
    assert lobby.planning_system == :custom
    assert lobby.custom_cards == ["S", "M", "L"]
    assert payload["cards"] == ["S", "M", "L"]
  end

  test "rejects a custom deck without cards" do
    response = execute(%{name: "Sprint 42", planning_system: "custom"})

    assert response.isError
  end

  test "rejects a blank name" do
    response = execute(%{name: "   "})

    assert response.isError
  end

  test "the first participant to join becomes the facilitator" do
    payload = execute(%{name: "Sprint 42"}) |> payload()
    lobby_id = payload["id"]

    {:ok, lobby} =
      LobbyServer.join(lobby_id, "user-1", %{name: "First", avatar: "🐶", role: :voter})

    assert lobby.creator_id == "user-1"

    {:ok, lobby} =
      LobbyServer.join(lobby_id, "user-2", %{name: "Second", avatar: "🐱", role: :voter})

    assert lobby.creator_id == "user-1"
  end

  test "an agent can queue items in a freshly created lobby" do
    payload = execute(%{name: "Sprint 42"}) |> payload()

    assert {:ok, _lobby} =
             LobbyServer.add_to_queue(payload["id"], "mcp_agent", %{
               id: "item-1",
               title: "Ticket"
             })
  end
end
