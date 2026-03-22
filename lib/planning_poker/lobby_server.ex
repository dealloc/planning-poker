defmodule PlanningPoker.LobbyServer do
  use GenServer

  alias PlanningPoker.Lobby

  @registry PlanningPoker.LobbyRegistry
  @supervisor PlanningPoker.LobbySupervisor

  # ── Client API ──────────────────────────────────────────────────────────────

  def create(attrs) do
    id = generate_id()
    attrs = Map.put(attrs, :id, id)

    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, attrs}) do
      {:ok, _pid} -> {:ok, id}
      {:ok, _pid, _info} -> {:ok, id}
      error -> error
    end
  end

  def get(lobby_id), do: call(lobby_id, :get)

  def join(lobby_id, user_id, user_attrs),
    do: call(lobby_id, {:join, user_id, user_attrs})

  def leave(lobby_id, user_id), do: cast(lobby_id, {:leave, user_id})

  def vote(lobby_id, user_id, card), do: call(lobby_id, {:vote, user_id, card})

  def set_status(lobby_id, user_id, status),
    do: cast(lobby_id, {:set_status, user_id, status})

  def start_item(lobby_id, creator_id, item),
    do: call(lobby_id, {:start_item, creator_id, item})

  def reveal_votes(lobby_id, creator_id),
    do: call(lobby_id, {:reveal_votes, creator_id})

  def reset_round(lobby_id, creator_id),
    do: call(lobby_id, {:reset_round, creator_id})

  def skip_item(lobby_id, creator_id),
    do: call(lobby_id, {:skip_item, creator_id})

  def kick(lobby_id, creator_id, user_id),
    do: call(lobby_id, {:kick, creator_id, user_id})

  def add_to_queue(lobby_id, creator_id, item),
    do: call(lobby_id, {:add_to_queue, creator_id, item})

  def remove_from_queue(lobby_id, creator_id, item_id),
    do: call(lobby_id, {:remove_from_queue, creator_id, item_id})

  def reorder_queue(lobby_id, creator_id, ids),
    do: cast(lobby_id, {:reorder_queue, creator_id, ids})

  def toggle_auto_reveal(lobby_id, creator_id),
    do: call(lobby_id, {:toggle_auto_reveal, creator_id})

  def throw_emoji(lobby_id, from_id, to_id, emoji),
    do: cast(lobby_id, {:throw_emoji, from_id, to_id, emoji})

  # ── Server callbacks ─────────────────────────────────────────────────────────

  def start_link(attrs) do
    GenServer.start_link(__MODULE__, attrs, name: via(attrs.id))
  end

  def child_spec(attrs) do
    %{
      id: {__MODULE__, attrs.id},
      start: {__MODULE__, :start_link, [attrs]},
      restart: :temporary
    }
  end

  @impl true
  def init(attrs) do
    {:ok, struct!(Lobby, attrs)}
  end

  @impl true
  def handle_call(:get, _from, lobby) do
    {:reply, {:ok, lobby}, lobby}
  end

  def handle_call({:join, user_id, user_attrs}, _from, lobby) do
    lobby = %{lobby | participants: Map.put(lobby.participants, user_id, user_attrs)}
    broadcast(lobby, {:lobby_updated, lobby})
    {:reply, {:ok, lobby}, lobby}
  end

  def handle_call({:vote, user_id, card}, _from, lobby) do
    cond do
      lobby.state != :voting ->
        {:reply, {:error, :not_voting}, lobby}

      not Map.has_key?(lobby.participants, user_id) ->
        {:reply, {:error, :not_participant}, lobby}

      true ->
        votes = Map.put(lobby.votes, user_id, card)
        lobby = %{lobby | votes: votes}

        voter_ids =
          lobby.participants
          |> Enum.filter(fn {_id, p} -> p.role == :voter end)
          |> Enum.map(&elem(&1, 0))

        lobby =
          if lobby.auto_reveal and Enum.all?(voter_ids, &Map.has_key?(votes, &1)) do
            do_reveal(lobby)
          else
            lobby
          end

        broadcast(lobby, {:lobby_updated, lobby})
        {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:start_item, creator_id, item}, _from, lobby) do
    if lobby.creator_id != creator_id do
      {:reply, {:error, :not_creator}, lobby}
    else
      queue = Enum.reject(lobby.queue, &(&1.id == item.id))
      lobby = %{lobby | state: :voting, current_item: item, votes: %{}, queue: queue}
      broadcast(lobby, {:lobby_updated, lobby})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:reveal_votes, creator_id}, _from, lobby) do
    if lobby.creator_id != creator_id do
      {:reply, {:error, :not_creator}, lobby}
    else
      lobby = do_reveal(lobby)
      broadcast(lobby, {:lobby_updated, lobby})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:reset_round, creator_id}, _from, lobby) do
    if lobby.creator_id != creator_id do
      {:reply, {:error, :not_creator}, lobby}
    else
      lobby = %{lobby | state: :waiting, votes: %{}, current_item: nil}
      broadcast(lobby, {:lobby_updated, lobby})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:skip_item, creator_id}, _from, lobby) do
    if lobby.creator_id != creator_id do
      {:reply, {:error, :not_creator}, lobby}
    else
      lobby = %{lobby | state: :waiting, votes: %{}, current_item: nil}
      broadcast(lobby, {:lobby_updated, lobby})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:kick, creator_id, user_id}, _from, lobby) do
    if lobby.creator_id != creator_id do
      {:reply, {:error, :not_creator}, lobby}
    else
      lobby = %{
        lobby
        | participants: Map.delete(lobby.participants, user_id),
          votes: Map.delete(lobby.votes, user_id)
      }

      broadcast(lobby, {:lobby_updated, lobby})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:add_to_queue, creator_id, item}, _from, lobby) do
    if lobby.creator_id != creator_id do
      {:reply, {:error, :not_creator}, lobby}
    else
      lobby = %{lobby | queue: lobby.queue ++ [item]}
      broadcast(lobby, {:lobby_updated, lobby})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:remove_from_queue, creator_id, item_id}, _from, lobby) do
    if lobby.creator_id != creator_id do
      {:reply, {:error, :not_creator}, lobby}
    else
      lobby = %{lobby | queue: Enum.reject(lobby.queue, &(&1.id == item_id))}
      broadcast(lobby, {:lobby_updated, lobby})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:toggle_auto_reveal, creator_id}, _from, lobby) do
    if lobby.creator_id != creator_id do
      {:reply, {:error, :not_creator}, lobby}
    else
      lobby = %{lobby | auto_reveal: not lobby.auto_reveal}
      broadcast(lobby, {:lobby_updated, lobby})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  @impl true
  def handle_cast({:leave, user_id}, lobby) do
    lobby = %{
      lobby
      | participants: Map.delete(lobby.participants, user_id),
        votes: Map.delete(lobby.votes, user_id)
    }

    broadcast(lobby, {:lobby_updated, lobby})
    {:noreply, lobby}
  end

  def handle_cast({:set_status, _user_id, _status}, lobby) do
    {:noreply, lobby}
  end

  def handle_cast({:throw_emoji, from_id, to_id, emoji}, lobby) do
    Phoenix.PubSub.broadcast(
      PlanningPoker.PubSub,
      topic(lobby.id),
      {:emoji_thrown, from_id, to_id, emoji}
    )

    {:noreply, lobby}
  end

  def handle_cast({:reorder_queue, creator_id, ids}, lobby) do
    lobby =
      if lobby.creator_id == creator_id do
        reordered = Enum.flat_map(ids, fn id -> Enum.filter(lobby.queue, &(&1.id == id)) end)
        missing = Enum.reject(lobby.queue, fn item -> item.id in ids end)
        updated = %{lobby | queue: reordered ++ missing}
        broadcast(updated, {:lobby_updated, updated})
        updated
      else
        lobby
      end

    {:noreply, lobby}
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp do_reveal(lobby) do
    stats = Lobby.compute_stats(lobby.votes)
    entry = %{item: lobby.current_item, votes: lobby.votes, stats: stats}
    %{lobby | state: :revealed, history: [entry | lobby.history]}
  end

  defp broadcast(lobby, message) do
    Phoenix.PubSub.broadcast(PlanningPoker.PubSub, topic(lobby.id), message)
  end

  defp topic(id), do: "lobby:#{id}"
  defp via(id), do: {:via, Registry, {@registry, id}}

  defp call(lobby_id, message) do
    case Registry.lookup(@registry, lobby_id) do
      [{pid, _}] -> GenServer.call(pid, message)
      [] -> {:error, :not_found}
    end
  end

  defp cast(lobby_id, message) do
    case Registry.lookup(@registry, lobby_id) do
      [{pid, _}] -> GenServer.cast(pid, message)
      [] -> :ok
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
  end
end
