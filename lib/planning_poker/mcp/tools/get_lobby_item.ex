defmodule PlanningPoker.MCP.Tools.GetLobbyItem do
  @moduledoc """
  Gets an existing item from the given lobby.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias PlanningPoker.LobbyServer

  schema do
    field(:lobby_id, :string, required: true, description: "The lobby ID")
    field(:item_id, :string, required: true, description: "The item ID to retrieve")
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
  def execute(%{lobby_id: lobby_id, item_id: item_id}, frame) do
    case LobbyServer.get(lobby_id) do
      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Lobby not found: #{lobby_id}"), frame}

      {:ok, lobby} ->
        queue_item = Enum.find(lobby.queue, &(&1.id == item_id))

        history_entry =
          Enum.find(lobby.history, fn entry ->
            entry.item != nil && entry.item.id == item_id
          end)

        cond do
          queue_item ->
            result = Map.put(queue_item, :source, "queue")
            {:reply, Response.json(Response.tool(), result), frame}

          history_entry ->
            result =
              history_entry.item
              |> Map.merge(%{
                source: "history",
                stats: history_entry.stats,
                duration_seconds: history_entry.duration_seconds,
                planning_system: Atom.to_string(history_entry.planning_system),
                note: history_entry.note
              })

            {:reply, Response.json(Response.tool(), result), frame}

          true ->
            {:reply, Response.error(Response.tool(), "Item not found: #{item_id}"), frame}
        end
    end
  end
end
