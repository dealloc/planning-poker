defmodule PlanningPoker.Metrics do
  @moduledoc """
  Collects global metrics about the application state.
  """

  alias PlanningPoker.LobbyRegistry

  def get_global_metrics do
    lobbies = list_all_lobbies()
    active_lobbies_count = length(lobbies)
    total_users = count_total_users(lobbies)
    memory_usage = get_memory_usage()

    %{
      active_lobbies: active_lobbies_count,
      total_users: total_users,
      memory_mb: memory_usage
    }
  end

  defp list_all_lobbies do
    Registry.select(LobbyRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  defp count_total_users(lobbies) do
    lobbies
    |> Enum.reduce(0, fn lobby_id, acc ->
      case PlanningPoker.LobbyServer.get(lobby_id) do
        {:ok, lobby} -> acc + map_size(lobby.participants)
        _ -> acc
      end
    end)
  end

  defp get_memory_usage do
    # Get total memory in use and convert to MB
    memory_bytes = :erlang.memory(:total)
    Float.round(memory_bytes / 1_048_576, 1)
  end
end
