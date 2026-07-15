defmodule PlanningPoker.LobbyServerTest do
  use ExUnit.Case, async: true

  alias PlanningPoker.LobbyServer

  defp create_lobby(creator_id) do
    {:ok, lobby_id} =
      LobbyServer.create(%{name: "Sprint Planning", creator_id: creator_id})

    :ok = LobbyServer.join(lobby_id, creator_id, %{name: "Host", avatar: "🐶", role: :voter})
    lobby_id
  end

  test "switching to spectator clears the participant's vote" do
    creator_id = "user-1"
    lobby_id = create_lobby(creator_id)

    {:ok, _} = LobbyServer.start_item(lobby_id, creator_id, %{id: "item-1", title: "Ticket"})
    {:ok, lobby} = LobbyServer.vote(lobby_id, creator_id, "5")
    assert lobby.votes[creator_id] == "5"

    {:ok, lobby} = LobbyServer.set_spectator(lobby_id, creator_id, true)

    refute Map.has_key?(lobby.votes, creator_id)
    assert lobby.participants[creator_id].role == :spectator
  end

  test "switching back to voter does not restore a cleared vote" do
    creator_id = "user-1"
    lobby_id = create_lobby(creator_id)

    {:ok, _} = LobbyServer.start_item(lobby_id, creator_id, %{id: "item-1", title: "Ticket"})
    {:ok, _} = LobbyServer.vote(lobby_id, creator_id, "5")
    {:ok, _} = LobbyServer.set_spectator(lobby_id, creator_id, true)
    {:ok, lobby} = LobbyServer.set_spectator(lobby_id, creator_id, false)

    refute Map.has_key?(lobby.votes, creator_id)
    assert lobby.participants[creator_id].role == :voter
  end
end
