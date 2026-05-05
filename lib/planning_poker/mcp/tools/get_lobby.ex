defmodule PlanningPoker.MCP.Tools.GetLobby do
  @moduledoc """
  Gets information about the active lobby.

  Returns the ID, the name, state, which planning system, the queue and current item (plus a few others).
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias PlanningPoker.LobbyServer

  schema do
    field(:lobby_id, :string, required: true, description: "The lobby ID")
  end

  @impl true
  def annotations() do
    %{
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "idempotentHint" => true,
      "openWorldHint" => false
    }
  end

  @impl true
  def execute(%{lobby_id: lobby_id}, frame) do
    case LobbyServer.get(lobby_id) do
      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Lobby not found: #{lobby_id}"), frame}

      {:ok, lobby} ->
        summary = %{
          id: lobby.id,
          name: lobby.name,
          state: Atom.to_string(lobby.state),
          planning_system: Atom.to_string(lobby.planning_system),
          members_can_add_to_queue: lobby.members_can_add_to_queue,
          queue: Enum.map(lobby.queue, &%{id: &1.id, title: &1.title}),
          current_item:
            if lobby.current_item do
              %{id: lobby.current_item.id, title: lobby.current_item.title}
            end,
          queue_length: length(lobby.queue),
          history_length: length(lobby.history)
        }

        {:reply, Response.json(Response.tool(), summary), frame}
    end
  end
end
