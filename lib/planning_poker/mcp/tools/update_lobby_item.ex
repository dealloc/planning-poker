defmodule PlanningPoker.MCP.Tools.UpdateLobbyItem do
  @moduledoc """
  Updates an already existing item within a given lobby.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias PlanningPoker.LobbyServer

  schema do
    field(:lobby_id, :string, required: true, description: "The lobby ID")
    field(:item_id, :string, required: true, description: "The item ID to update")

    field(:title, :string,
      required: false,
      description: "New title (optional if description is provided)"
    )

    field(:description, :string,
      required: false,
      description: "New description (optional if title is provided)"
    )

    field(:context_url, :string,
      required: false,
      description: "New URL linking to the ticket or relevant context (e.g. Jira, GitHub issue)"
    )
  end

  @impl true
  def annotations() do
    %{
      "readOnlyHint" => false,
      "destructiveHint" => false,
      "idempotentHint" => true,
      "openWorldHint" => false
    }
  end

  @impl true
  def execute(params, frame) do
    title = Map.get(params, :title)
    description = Map.get(params, :description)
    context_url = Map.get(params, :context_url)

    if is_nil(title) and is_nil(description) and is_nil(context_url) do
      {:reply,
       Response.error(
         Response.tool(),
         "At least one of title, description, or context_url must be provided."
       ),
       frame}
    else
      case LobbyServer.get(params.lobby_id) do
        {:error, :not_found} ->
          {:reply, Response.error(Response.tool(), "Lobby not found: #{params.lobby_id}"), frame}

        {:ok, lobby} ->
          if Enum.find(lobby.queue, &(&1.id == params.item_id)) do
            case LobbyServer.update_queue_item(
                   params.lobby_id,
                   params.item_id,
                   title,
                   description,
                   context_url
                 ) do
              {:ok, _lobby} ->
                {:reply,
                 Response.json(Response.tool(), %{
                   id: params.item_id,
                   message: "Item updated successfully"
                 }), frame}

              {:error, :not_found} ->
                {:reply, Response.error(Response.tool(), "Item not found in queue."), frame}
            end
          else
            {:reply,
             Response.error(
               Response.tool(),
               "Item not found in queue. Only queued items can be updated (not current_item or history)."
             ), frame}
          end
      end
    end
  end
end
