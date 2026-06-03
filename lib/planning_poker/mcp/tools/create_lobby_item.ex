defmodule PlanningPoker.MCP.Tools.CreateLobbyItem do
  @moduledoc """
  Creates a new item in the given lobby.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias PlanningPoker.LobbyServer

  schema do
    field(:lobby_id, :string, required: true, description: "The lobby ID")
    field(:title, :string, required: true, description: "Item title (e.g. ticket name)")

    field(:description, :string,
      required: false,
      description: "Full description or acceptance criteria (recommended)"
    )

    field(:context_url, :string,
      required: false,
      description: "URL linking to the ticket or relevant context (e.g. Jira, GitHub issue)"
    )
  end

  @impl true
  def annotations() do
    %{
      "readOnlyHint" => false,
      "destructiveHint" => false,
      "idempotentHint" => false,
      "openWorldHint" => false
    }
  end

  @impl true
  def execute(params, frame) do
    lobby_id = params.lobby_id

    case LobbyServer.get(lobby_id) do
      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Lobby not found: #{lobby_id}"), frame}

      {:ok, lobby} ->
        if not lobby.members_can_add_to_queue do
          {:reply,
           Response.error(
             Response.tool(),
             "This lobby does not allow members to add items. The host must enable 'Members can add to queue' in lobby settings."
           ), frame}
        else
          id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

          item = %{
            id: id,
            title: params.title,
            description: Map.get(params, :description),
            context_url: Map.get(params, :context_url)
          }

          case LobbyServer.add_to_queue(lobby_id, "mcp_agent", item) do
            {:ok, _lobby} ->
              {:reply,
               Response.json(Response.tool(), %{
                 id: id,
                 title: params.title,
                 message: "Item added to queue successfully"
               }), frame}

            {:error, :not_creator} ->
              {:reply,
               Response.error(Response.tool(), "Queue is not open to members in this lobby."),
               frame}
          end
        end
    end
  end
end
