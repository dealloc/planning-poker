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

  def toggle_members_queue(lobby_id, creator_id),
    do: call(lobby_id, {:toggle_members_queue, creator_id})

  def transfer_host(lobby_id, from_id, to_id),
    do: call(lobby_id, {:transfer_host, from_id, to_id})

  def accept_host_transfer(lobby_id, user_id),
    do: call(lobby_id, {:accept_host_transfer, user_id})

  def decline_host_transfer(lobby_id, user_id),
    do: call(lobby_id, {:decline_host_transfer, user_id})

  def throw_emoji(lobby_id, from_id, to_id, emoji),
    do: cast(lobby_id, {:throw_emoji, from_id, to_id, emoji})

  def set_spectator(lobby_id, user_id, spectating?),
    do: call(lobby_id, {:set_spectator, user_id, spectating?})

  def update_history_note(lobby_id, item_id, note),
    do: call(lobby_id, {:update_history_note, item_id, note})

  def change_planning_system(lobby_id, creator_id, system),
    do: call(lobby_id, {:change_planning_system, creator_id, system})

  def add_vote_note(lobby_id, user_id, note),
    do: call(lobby_id, {:add_vote_note, user_id, note})

  def change_avatar(lobby_id, user_id, avatar),
    do: cast(lobby_id, {:change_avatar, user_id, avatar})

  def buzz(lobby_id, from_id, to_id),
    do: cast(lobby_id, {:buzz, from_id, to_id})

  def update_item_description(lobby_id, creator_id, item_id, description),
    do: call(lobby_id, {:update_item_description, creator_id, item_id, description})

  def update_queue_item(lobby_id, item_id, title, description),
    do: call(lobby_id, {:update_queue_item, item_id, title, description})

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

      lobby = %{
        lobby
        | state: :voting,
          current_item: item,
          votes: %{},
          vote_notes: %{},
          queue: queue,
          opened_at: lobby.opened_at || DateTime.utc_now(),
          voting_started_at: DateTime.utc_now()
      }

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
      lobby = %{lobby | state: :waiting, votes: %{}, vote_notes: %{}, current_item: nil}
      broadcast(lobby, {:lobby_updated, lobby})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:skip_item, creator_id}, _from, lobby) do
    if lobby.creator_id != creator_id do
      {:reply, {:error, :not_creator}, lobby}
    else
      lobby = %{lobby | state: :waiting, votes: %{}, vote_notes: %{}, current_item: nil}
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

  def handle_call({:add_to_queue, user_id, item}, _from, lobby) do
    if lobby.creator_id != user_id and not lobby.members_can_add_to_queue do
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

  def handle_call({:toggle_members_queue, creator_id}, _from, lobby) do
    if lobby.creator_id != creator_id do
      {:reply, {:error, :not_creator}, lobby}
    else
      lobby = %{lobby | members_can_add_to_queue: not lobby.members_can_add_to_queue}
      broadcast(lobby, {:lobby_updated, lobby})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:transfer_host, from_id, to_id}, _from, lobby) do
    cond do
      lobby.creator_id != from_id ->
        {:reply, {:error, :not_creator}, lobby}

      not Map.has_key?(lobby.participants, to_id) ->
        {:reply, {:error, :not_participant}, lobby}

      true ->
        lobby = %{lobby | pending_host_transfer: to_id}
        broadcast(lobby, {:host_transfer_offered, to_id})
        {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:accept_host_transfer, user_id}, _from, lobby) do
    if lobby.pending_host_transfer != user_id do
      {:reply, {:error, :not_offered}, lobby}
    else
      lobby = %{lobby | creator_id: user_id, pending_host_transfer: nil}
      broadcast(lobby, {:lobby_updated, lobby})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:decline_host_transfer, user_id}, _from, lobby) do
    if lobby.pending_host_transfer != user_id do
      {:reply, {:error, :not_offered}, lobby}
    else
      lobby = %{lobby | pending_host_transfer: nil}
      broadcast(lobby, {:host_transfer_declined, user_id})
      {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:set_spectator, user_id, spectating?}, _from, lobby) do
    case Map.get(lobby.participants, user_id) do
      nil ->
        {:reply, {:error, :not_participant}, lobby}

      participant ->
        role = if spectating?, do: :spectator, else: :voter
        updated = %{participant | role: role}
        lobby = %{lobby | participants: Map.put(lobby.participants, user_id, updated)}
        broadcast(lobby, {:lobby_updated, lobby})
        {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:change_planning_system, creator_id, system}, _from, lobby) do
    cond do
      lobby.creator_id != creator_id ->
        {:reply, {:error, :not_creator}, lobby}

      lobby.state == :voting ->
        {:reply, {:error, :voting_in_progress}, lobby}

      true ->
        lobby = %{lobby | planning_system: system}
        broadcast(lobby, {:lobby_updated, lobby})
        {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:add_vote_note, user_id, note}, _from, lobby) do
    cond do
      lobby.state not in [:voting, :revealed] ->
        {:reply, {:error, :not_voting}, lobby}

      not Map.has_key?(lobby.participants, user_id) ->
        {:reply, {:error, :not_participant}, lobby}

      not Map.has_key?(lobby.votes, user_id) ->
        {:reply, {:error, :no_vote}, lobby}

      true ->
        note_value = if is_binary(note) && String.trim(note) == "", do: nil, else: note
        lobby = %{lobby | vote_notes: Map.put(lobby.vote_notes, user_id, note_value)}
        broadcast(lobby, {:lobby_updated, lobby})
        {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:update_history_note, item_id, note}, _from, lobby) do
    history =
      Enum.map(lobby.history, fn entry ->
        if entry.item && entry.item.id == item_id do
          %{entry | note: note}
        else
          entry
        end
      end)

    lobby = %{lobby | history: history}
    broadcast(lobby, {:lobby_updated, lobby})
    {:reply, {:ok, lobby}, lobby}
  end

  def handle_call({:update_queue_item, item_id, title, description}, _from, lobby) do
    case Enum.find(lobby.queue, &(&1.id == item_id)) do
      nil ->
        {:reply, {:error, :not_found}, lobby}

      _item ->
        queue =
          Enum.map(lobby.queue, fn item ->
            if item.id == item_id do
              item
              |> then(fn i -> if title, do: Map.put(i, :title, title), else: i end)
              |> then(fn i -> if description != nil, do: Map.put(i, :description, description), else: i end)
            else
              item
            end
          end)

        lobby = %{lobby | queue: queue}
        broadcast(lobby, {:lobby_updated, lobby})
        {:reply, {:ok, lobby}, lobby}
    end
  end

  def handle_call({:update_item_description, creator_id, item_id, description}, _from, lobby) do
    if lobby.creator_id != creator_id do
      {:reply, {:error, :not_creator}, lobby}
    else
      description_value =
        if is_binary(description) && String.trim(description) == "", do: nil, else: description

      lobby =
        cond do
          lobby.current_item && lobby.current_item.id == item_id ->
            %{lobby | current_item: Map.put(lobby.current_item, :description, description_value)}

          true ->
            queue =
              Enum.map(lobby.queue, fn item ->
                if item.id == item_id,
                  do: Map.put(item, :description, description_value),
                  else: item
              end)

            %{lobby | queue: queue}
        end

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

  def handle_cast({:change_avatar, user_id, avatar}, lobby) do
    case Map.get(lobby.participants, user_id) do
      nil ->
        {:noreply, lobby}

      participant ->
        updated = %{participant | avatar: avatar}
        lobby = %{lobby | participants: Map.put(lobby.participants, user_id, updated)}
        broadcast(lobby, {:lobby_updated, lobby})
        {:noreply, lobby}
    end
  end

  def handle_cast({:buzz, _from_id, to_id}, lobby) do
    now = DateTime.utc_now()

    cond do
      lobby.state != :voting ->
        {:noreply, lobby}

      Map.has_key?(lobby.votes, to_id) ->
        {:noreply, lobby}

      lobby.buzz_cooldown_until &&
          DateTime.compare(now, lobby.buzz_cooldown_until) == :lt ->
        {:noreply, lobby}

      true ->
        lobby = %{lobby | buzz_cooldown_until: DateTime.add(now, 10, :second)}
        Phoenix.PubSub.broadcast(PlanningPoker.PubSub, topic(lobby.id), {:buzzed, to_id})
        {:noreply, lobby}
    end
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
    spectator_ids =
      lobby.participants
      |> Enum.filter(fn {_id, p} -> p.role == :spectator end)
      |> Enum.map(&elem(&1, 0))

    votes = Map.drop(lobby.votes, spectator_ids)
    stats = Lobby.compute_stats(votes)

    duration_seconds =
      if lobby.voting_started_at do
        DateTime.diff(DateTime.utc_now(), lobby.voting_started_at, :second)
      else
        nil
      end

    entry = %{
      item: lobby.current_item,
      votes: votes,
      vote_notes: lobby.vote_notes,
      stats: stats,
      duration_seconds: duration_seconds,
      note: nil,
      planning_system: lobby.planning_system
    }

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
