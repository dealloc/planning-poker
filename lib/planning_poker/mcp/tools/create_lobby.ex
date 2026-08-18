defmodule PlanningPoker.MCP.Tools.CreateLobby do
  @moduledoc """
  Creates a new lobby.

  The lobby starts without a host: the first person to open the returned URL
  becomes the facilitator.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias PlanningPoker.Lobby
  alias PlanningPoker.LobbyServer

  @planning_systems Enum.map(Lobby.planning_systems(), fn {system, _label} ->
                      Atom.to_string(system)
                    end)

  schema do
    field(:name, :string,
      required: true,
      description: "Name of the lobby (e.g. the sprint or team name)"
    )

    field(:planning_system, {:enum, @planning_systems},
      required: false,
      description:
        "Card deck to estimate with. Defaults to \"fibonacci\". Use \"custom\" together with custom_cards."
    )

    field(:custom_cards, {:list, :string},
      required: false,
      description:
        "Card values to use when planning_system is \"custom\", e.g. [\"S\", \"M\", \"L\"]"
    )

    field(:auto_reveal, :boolean,
      required: false,
      description: "Reveal the votes automatically once everyone has voted. Defaults to false."
    )

    field(:members_can_add_to_queue, :boolean,
      required: false,
      description:
        "Allow anyone (including this MCP server) to add items to the queue. Defaults to true."
    )

    field(:discussion_threshold_minutes, :integer,
      required: false,
      description: "Warn the lobby when a single item takes longer than this many minutes"
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
    name = params |> value(:name, "") |> String.trim()

    planning_system = params |> value(:planning_system, "fibonacci") |> String.to_existing_atom()

    custom_cards = params |> Map.get(:custom_cards) |> normalize_cards()

    cond do
      name == "" ->
        {:reply, Response.error(Response.tool(), "Lobby name cannot be empty."), frame}

      planning_system == :custom and custom_cards == [] ->
        {:reply,
         Response.error(
           Response.tool(),
           "custom_cards is required when planning_system is \"custom\"."
         ), frame}

      true ->
        attrs = %{
          name: name,
          creator_id: nil,
          planning_system: planning_system,
          custom_cards: custom_cards,
          auto_reveal: value(params, :auto_reveal, false),
          members_can_add_to_queue: value(params, :members_can_add_to_queue, true),
          discussion_threshold_seconds:
            threshold_seconds(Map.get(params, :discussion_threshold_minutes))
        }

        case LobbyServer.create(attrs) do
          {:ok, lobby_id} ->
            {:reply,
             Response.json(Response.tool(), %{
               id: lobby_id,
               name: name,
               url: lobby_url(lobby_id),
               planning_system: Atom.to_string(planning_system),
               cards: cards(planning_system, custom_cards),
               message:
                 "Lobby created. Share the URL — the first person to join becomes the facilitator."
             }), frame}

          {:error, reason} ->
            {:reply,
             Response.error(Response.tool(), "Failed to create lobby: #{inspect(reason)}"), frame}
        end
    end
  end

  # Optional fields are absent when omitted, but a client may also send them as
  # an explicit null.
  defp value(params, key, default) do
    case Map.get(params, key) do
      nil -> default
      value -> value
    end
  end

  defp cards(:custom, custom_cards), do: custom_cards
  defp cards(planning_system, _custom_cards), do: Lobby.cards(planning_system)

  defp normalize_cards(nil), do: []

  defp normalize_cards(cards) when is_list(cards) do
    cards
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp threshold_seconds(minutes) when is_integer(minutes) and minutes > 0, do: minutes * 60
  defp threshold_seconds(_), do: nil

  defp lobby_url(lobby_id) do
    PlanningPokerWeb.Endpoint.url() <> "/lobby/" <> lobby_id
  end
end
