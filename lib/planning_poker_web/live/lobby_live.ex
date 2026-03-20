defmodule PlanningPokerWeb.LobbyLive do
  use PlanningPokerWeb, :live_view

  alias PlanningPoker.{LobbyServer, Presence}

  @throw_emojis ["👍", "👎", "🎉", "❤️", "😂", "🤔", "🔥", "💩", "🚀", "⭐"]

  # ── Mount ────────────────────────────────────────────────────────────────────

  @impl true
  def mount(%{"id" => lobby_id}, session, socket) do
    user_id = session["user_id"]
    user_name = session["user_name"]
    user_avatar = session["user_avatar"] || "🐶"

    cond do
      !user_id || !user_name || user_name == "" ->
        {:ok, push_navigate(socket, to: ~p"/?join=#{lobby_id}")}

      true ->
        user_attrs = %{name: user_name, avatar: user_avatar, role: :voter}

        case LobbyServer.join(lobby_id, user_id, user_attrs) do
          {:ok, lobby} ->
            if connected?(socket) do
              Phoenix.PubSub.subscribe(PlanningPoker.PubSub, "lobby:#{lobby_id}")

              Presence.track(self(), "lobby:#{lobby_id}", user_id, %{
                name: user_name,
                avatar: user_avatar,
                status: :voting
              })
            end

            presence = Presence.list("lobby:#{lobby_id}")

            socket =
              socket
              |> assign(:lobby, lobby)
              |> assign(:current_user_id, user_id)
              |> assign(:presence, presence)
              |> assign(:my_vote, Map.get(lobby.votes, user_id))
              |> assign(:show_queue_form, false)
              |> assign(:show_start_form, false)
              |> assign(:throw_emojis, @throw_emojis)
              |> assign(:start_form, to_form(%{"title" => "", "context_url" => ""}))
              |> assign(:queue_form, to_form(%{"title" => "", "context_url" => ""}))
              |> assign(:page_title, lobby.name)

            {:ok, socket}

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(:error, "Lobby not found.")
             |> push_navigate(to: ~p"/")}
        end
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:lobby] do
      LobbyServer.leave(socket.assigns.lobby.id, socket.assigns.current_user_id)
    end
  end

  # ── Events ───────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("vote", %{"card" => card}, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns

    case LobbyServer.vote(lobby.id, uid, card) do
      {:ok, _lobby} -> {:noreply, assign(socket, :my_vote, card)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("reveal", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.reveal_votes(lobby.id, uid)
    {:noreply, socket}
  end

  def handle_event("reset_round", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.reset_round(lobby.id, uid)
    {:noreply, assign(socket, :my_vote, nil)}
  end

  def handle_event("next_item", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns

    case lobby.queue do
      [item | _] ->
        LobbyServer.start_item(lobby.id, uid, item)
        {:noreply, assign(socket, :my_vote, nil)}

      [] ->
        {:noreply, put_flash(socket, :error, "Queue is empty")}
    end
  end

  def handle_event("skip_item", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.skip_item(lobby.id, uid)
    {:noreply, assign(socket, :my_vote, nil)}
  end

  def handle_event("start_item", %{"title" => title, "context_url" => url}, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    item = %{id: generate_id(), title: String.trim(title), context_url: nilify(url)}
    LobbyServer.start_item(lobby.id, uid, item)

    {:noreply,
     socket
     |> assign(:my_vote, nil)
     |> assign(:show_start_form, false)
     |> assign(:start_form, to_form(%{"title" => "", "context_url" => ""}))}
  end

  def handle_event("add_to_queue", %{"title" => title, "context_url" => url}, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    item = %{id: generate_id(), title: String.trim(title), context_url: nilify(url)}
    LobbyServer.add_to_queue(lobby.id, uid, item)

    {:noreply,
     socket
     |> assign(:show_queue_form, false)
     |> assign(:queue_form, to_form(%{"title" => "", "context_url" => ""}))}
  end

  def handle_event("remove_from_queue", %{"id" => item_id}, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.remove_from_queue(lobby.id, uid, item_id)
    {:noreply, socket}
  end

  def handle_event("toggle_auto_reveal", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.toggle_auto_reveal(lobby.id, uid)
    {:noreply, socket}
  end

  def handle_event("kick", %{"user-id" => user_id}, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.kick(lobby.id, uid, user_id)
    {:noreply, socket}
  end

  def handle_event("throw_emoji", %{"to" => to_id, "emoji" => emoji}, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.throw_emoji(lobby.id, uid, to_id, emoji)
    {:noreply, socket}
  end

  def handle_event("toggle_start_form", _params, socket) do
    {:noreply, assign(socket, :show_start_form, not socket.assigns.show_start_form)}
  end

  def handle_event("toggle_queue_form", _params, socket) do
    {:noreply, assign(socket, :show_queue_form, not socket.assigns.show_queue_form)}
  end

  def handle_event("blur", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns

    Presence.update(self(), "lobby:#{lobby.id}", uid, fn meta ->
      %{meta | status: :reading}
    end)

    LobbyServer.set_status(lobby.id, uid, :reading)
    {:noreply, socket}
  end

  def handle_event("focus", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns

    Presence.update(self(), "lobby:#{lobby.id}", uid, fn meta ->
      %{meta | status: :voting}
    end)

    LobbyServer.set_status(lobby.id, uid, :voting)
    {:noreply, socket}
  end

  # ── PubSub messages ──────────────────────────────────────────────────────────

  @impl true
  def handle_info({:lobby_updated, lobby}, socket) do
    my_vote = Map.get(lobby.votes, socket.assigns.current_user_id)
    {:noreply, socket |> assign(:lobby, lobby) |> assign(:my_vote, my_vote)}
  end

  def handle_info({:emoji_thrown, from, to, emoji}, socket) do
    socket =
      push_event(socket, "emoji_thrown", %{
        from: from,
        to: to,
        emoji: emoji,
        target_el: "participant-#{to}"
      })

    {:noreply, socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    presence = Presence.list("lobby:#{socket.assigns.lobby.id}")
    {:noreply, assign(socket, :presence, presence)}
  end

  # ── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} inner_class="w-full max-w-7xl mx-auto px-4 sm:px-6">
      <div
        id="lobby-root"
        phx-window-blur="blur"
        phx-window-focus="focus"
        phx-hook=".EmojiThrow"
        class="pb-12"
      >
        <%!-- Header --%>
        <div class="flex flex-wrap items-center justify-between gap-4 py-6 border-b border-base-300 mb-8">
          <div>
            <h1 class="text-2xl font-bold text-base-content">{@lobby.name}</h1>
            <div class="flex items-center gap-3 mt-1">
              <span class={[
                "inline-flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded-full",
                @lobby.state == :waiting && "bg-base-300 text-base-content/60",
                @lobby.state == :voting && "bg-warning/20 text-warning",
                @lobby.state == :revealed && "bg-success/20 text-success"
              ]}>
                <%= case @lobby.state do %>
                  <% :waiting -> %>
                    <span class="size-1.5 rounded-full bg-base-content/40 inline-block"></span>
                    Waiting
                  <% :voting -> %>
                    <span class="size-1.5 rounded-full bg-warning inline-block animate-pulse"></span>
                    Voting
                  <% :revealed -> %>
                    <span class="size-1.5 rounded-full bg-success inline-block"></span> Revealed
                <% end %>
              </span>

              <span class="text-xs text-base-content/40">
                {Atom.to_string(@lobby.planning_system)
                |> String.replace("_", " ")
                |> String.capitalize()}
              </span>
            </div>
          </div>

          <div class="flex items-center gap-3">
            <%!-- Auto-reveal toggle (creator only) --%>
            <%= if @current_user_id == @lobby.creator_id do %>
              <button
                id="toggle-auto-reveal"
                phx-click="toggle_auto_reveal"
                class={[
                  "flex items-center gap-2 text-sm px-3 py-1.5 rounded-lg border transition-colors cursor-pointer",
                  if(@lobby.auto_reveal,
                    do: "bg-primary/10 border-primary/30 text-primary",
                    else: "bg-base-200 border-base-300 text-base-content/60 hover:border-base-400"
                  )
                ]}
              >
                <.icon name="hero-bolt-micro" class="size-3.5" /> Auto-reveal
              </button>
            <% end %>

            <%!-- Share link --%>
            <div class="flex items-center gap-1.5 bg-base-200 border border-base-300 rounded-lg px-3 py-1.5">
              <.icon name="hero-link-micro" class="size-3.5 text-base-content/50" />
              <span class="text-xs font-mono text-base-content/60">{@lobby.id}</span>
            </div>
          </div>
        </div>

        <%!-- Main layout: voting area + participants --%>
        <div class="grid grid-cols-1 lg:grid-cols-[1fr_280px] gap-8">
          <%!-- Left: Voting area --%>
          <div>
            <%!-- Current item --%>
            <%= if @lobby.current_item do %>
              <div class="bg-base-200 rounded-xl p-6 mb-6 border border-base-300">
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <p class="text-xs text-base-content/50 uppercase tracking-wider font-medium mb-1">
                      Current item
                    </p>
                    <h2 class="text-xl font-semibold text-base-content">
                      {@lobby.current_item.title}
                    </h2>
                    <%= if @lobby.current_item.context_url do %>
                      <a
                        href={@lobby.current_item.context_url}
                        target="_blank"
                        rel="noopener"
                        class="inline-flex items-center gap-1 text-xs text-primary hover:underline mt-1"
                      >
                        <.icon name="hero-arrow-top-right-on-square-micro" class="size-3" />
                        {URI.parse(@lobby.current_item.context_url).host}
                      </a>
                    <% end %>
                  </div>

                  <%!-- Creator actions during voting/revealed --%>
                  <%= if @current_user_id == @lobby.creator_id do %>
                    <div class="flex gap-2 flex-shrink-0">
                      <%= if @lobby.state == :voting do %>
                        <button
                          id="reveal-btn"
                          phx-click="reveal"
                          class="btn btn-sm btn-primary"
                        >
                          Reveal
                        </button>
                      <% end %>
                      <%= if @lobby.state == :revealed do %>
                        <button
                          id="reset-btn"
                          phx-click="reset_round"
                          class="btn btn-sm btn-ghost"
                        >
                          Re-vote
                        </button>
                        <%= if @lobby.queue != [] do %>
                          <button
                            id="next-item-btn"
                            phx-click="next_item"
                            class="btn btn-sm btn-primary"
                          >
                            Next →
                          </button>
                        <% end %>
                      <% end %>
                      <button
                        id="skip-btn"
                        phx-click="skip_item"
                        class="btn btn-sm btn-ghost text-base-content/50"
                      >
                        Skip
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Stats (revealed state) --%>
            <%= if @lobby.state == :revealed && @lobby.current_item do %>
              <%!-- Compute stats from the last history entry (or current votes) --%>
              <%!-- The votes are still in lobby.votes during revealed state --%>
              <% stats = PlanningPoker.Lobby.compute_stats(@lobby.votes) %>
              <div class="bg-base-200 rounded-xl p-6 mb-6 border border-base-300">
                <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
                  Results
                </h3>
                <%= if stats.consensus? do %>
                  <div class="flex items-center gap-2 mb-4 text-success font-semibold">
                    <span class="text-2xl">🎉</span>
                    Consensus! Everyone voted <span class="font-mono">{stats.avg}</span>
                  </div>
                <% end %>
                <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-4">
                  <%= if stats.avg do %>
                    <div class="text-center bg-base-100 rounded-lg p-3">
                      <div class="text-2xl font-bold text-primary">{stats.avg}</div>
                      <div class="text-xs text-base-content/50 mt-0.5">Average</div>
                    </div>
                    <div class="text-center bg-base-100 rounded-lg p-3">
                      <div class="text-2xl font-bold text-base-content">{stats.median}</div>
                      <div class="text-xs text-base-content/50 mt-0.5">Median</div>
                    </div>
                    <div class="text-center bg-base-100 rounded-lg p-3">
                      <div class="text-2xl font-bold text-base-content">{stats.min}</div>
                      <div class="text-xs text-base-content/50 mt-0.5">Min</div>
                    </div>
                    <div class="text-center bg-base-100 rounded-lg p-3">
                      <div class="text-2xl font-bold text-base-content">{stats.max}</div>
                      <div class="text-xs text-base-content/50 mt-0.5">Max</div>
                    </div>
                  <% else %>
                    <div class="col-span-4 text-center text-base-content/50 py-2">
                      No numeric votes cast.
                    </div>
                  <% end %>
                </div>
                <%!-- Distribution --%>
                <div class="flex flex-wrap gap-2">
                  <%= for {card, count} <- Enum.sort_by(stats.distribution, fn {k, _} -> k end) do %>
                    <div class="flex items-center gap-1.5 bg-base-100 rounded-lg px-3 py-1.5">
                      <span class="font-mono font-semibold text-base-content">{card}</span>
                      <span class="text-xs text-base-content/50">×{count}</span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Voting cards --%>
            <%= if @lobby.state == :voting do %>
              <% cards = PlanningPoker.Lobby.cards(@lobby.planning_system) %>
              <div class="mb-6">
                <p class="text-sm text-base-content/50 mb-4">
                  <%= if @my_vote do %>
                    You voted <span class="font-mono font-bold text-primary">{@my_vote}</span>
                    — click another to change.
                  <% else %>
                    Pick a card to cast your vote.
                  <% end %>
                </p>
                <div class="flex flex-wrap gap-3">
                  <%= for card <- cards do %>
                    <button
                      id={"card-#{card}"}
                      phx-click="vote"
                      phx-value-card={card}
                      class={[
                        "relative w-16 h-24 rounded-xl border-2 text-xl font-bold",
                        "flex items-center justify-center cursor-pointer select-none",
                        "transition-all duration-150 hover:-translate-y-1 hover:shadow-lg",
                        if(@my_vote == card,
                          do:
                            "bg-primary text-primary-content border-primary shadow-lg -translate-y-2 scale-105",
                          else:
                            "bg-base-200 border-base-300 text-base-content hover:border-primary/50"
                        )
                      ]}
                    >
                      {card}
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Waiting state: creator controls --%>
            <%= if @lobby.state == :waiting && @current_user_id == @lobby.creator_id do %>
              <div class="space-y-4">
                <%!-- Start item inline --%>
                <%= if not @show_start_form do %>
                  <div class="flex gap-3">
                    <button
                      id="start-item-toggle"
                      phx-click="toggle_start_form"
                      class="btn btn-primary"
                    >
                      <.icon name="hero-play-micro" class="size-4" /> Start item
                    </button>
                    <%= if @lobby.queue != [] do %>
                      <button
                        id="next-from-queue-btn"
                        phx-click="next_item"
                        class="btn btn-ghost"
                      >
                        Next from queue ({length(@lobby.queue)})
                      </button>
                    <% end %>
                  </div>
                <% else %>
                  <div class="bg-base-200 rounded-xl p-5 border border-base-300">
                    <h3 class="font-semibold mb-4 text-base-content">Start a new item</h3>
                    <.form for={@start_form} id="start-item-form" phx-submit="start_item">
                      <.input
                        field={@start_form[:title]}
                        type="text"
                        label="Item title"
                        placeholder="User story, task, or feature…"
                        required
                        autocomplete="off"
                      />
                      <.input
                        field={@start_form[:context_url]}
                        type="url"
                        label="Link (optional)"
                        placeholder="https://…"
                        autocomplete="off"
                      />
                      <div class="flex gap-2 mt-2">
                        <button type="submit" class="btn btn-primary btn-sm">Start voting</button>
                        <button
                          type="button"
                          phx-click="toggle_start_form"
                          class="btn btn-ghost btn-sm"
                        >
                          Cancel
                        </button>
                      </div>
                    </.form>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%!-- Waiting state, non-creator --%>
            <%= if @lobby.state == :waiting && @current_user_id != @lobby.creator_id do %>
              <div class="flex flex-col items-center justify-center py-16 text-center">
                <div class="text-5xl mb-4">⏳</div>
                <p class="text-lg font-medium text-base-content/60">
                  Waiting for the facilitator to start a round…
                </p>
              </div>
            <% end %>

            <%!-- Queue --%>
            <%= if @current_user_id == @lobby.creator_id do %>
              <div class="mt-8">
                <div class="flex items-center justify-between mb-4">
                  <h3 class="font-semibold text-base-content/80">
                    Queue
                    <%= if @lobby.queue != [] do %>
                      <span class="ml-1.5 text-xs bg-base-300 text-base-content/60 px-1.5 py-0.5 rounded-full">
                        {length(@lobby.queue)}
                      </span>
                    <% end %>
                  </h3>
                  <button
                    id="toggle-queue-form"
                    phx-click="toggle_queue_form"
                    class="btn btn-ghost btn-xs"
                  >
                    <.icon name="hero-plus-micro" class="size-3.5" /> Add
                  </button>
                </div>

                <%= if @show_queue_form do %>
                  <div class="bg-base-200 rounded-xl p-4 mb-4 border border-base-300">
                    <.form for={@queue_form} id="queue-form" phx-submit="add_to_queue">
                      <.input
                        field={@queue_form[:title]}
                        type="text"
                        label="Item title"
                        placeholder="User story or task…"
                        required
                        autocomplete="off"
                      />
                      <.input
                        field={@queue_form[:context_url]}
                        type="url"
                        label="Link (optional)"
                        placeholder="https://…"
                        autocomplete="off"
                      />
                      <div class="flex gap-2 mt-2">
                        <button type="submit" class="btn btn-primary btn-sm">Add to queue</button>
                        <button
                          type="button"
                          phx-click="toggle_queue_form"
                          class="btn btn-ghost btn-sm"
                        >
                          Cancel
                        </button>
                      </div>
                    </.form>
                  </div>
                <% end %>

                <%= if @lobby.queue == [] && not @show_queue_form do %>
                  <p class="text-sm text-base-content/40 py-3">
                    No items in queue. Add stories to plan them ahead of time.
                  </p>
                <% end %>

                <div class="space-y-2">
                  <%= for item <- @lobby.queue do %>
                    <div
                      id={"queue-item-#{item.id}"}
                      class="flex items-center gap-3 bg-base-200 rounded-lg px-4 py-2.5 border border-base-300 group"
                    >
                      <span class="flex-1 text-sm text-base-content truncate">{item.title}</span>
                      <button
                        phx-click="remove_from_queue"
                        phx-value-id={item.id}
                        class="opacity-0 group-hover:opacity-100 transition-opacity text-base-content/40 hover:text-error cursor-pointer"
                        aria-label="Remove"
                      >
                        <.icon name="hero-x-mark-micro" class="size-4" />
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- History --%>
            <%= if @lobby.history != [] do %>
              <div class="mt-10">
                <h3 class="font-semibold text-base-content/80 mb-4">History</h3>
                <div class="space-y-3">
                  <%= for entry <- @lobby.history do %>
                    <div
                      id={"history-#{entry.item && entry.item.id}"}
                      class="bg-base-200 rounded-xl px-5 py-4 border border-base-300"
                    >
                      <div class="flex items-center justify-between gap-4">
                        <span class="text-sm font-medium text-base-content">
                          {entry.item && entry.item.title}
                        </span>
                        <div class="flex items-center gap-3 flex-shrink-0">
                          <%= if entry.stats.avg do %>
                            <span class="text-xs text-base-content/50">
                              avg
                              <span class="font-mono font-semibold text-base-content">
                                {entry.stats.avg}
                              </span>
                            </span>
                          <% end %>
                          <%= if entry.stats.consensus? do %>
                            <span class="text-xs bg-success/20 text-success px-2 py-0.5 rounded-full font-medium">
                              ✓ Consensus
                            </span>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Right: Participant list --%>
          <div>
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
              Participants ({map_size(@lobby.participants)})
            </h3>

            <div class="space-y-2">
              <%= for {pid, participant} <- @lobby.participants do %>
                <% presence_meta = get_presence_meta(@presence, pid) %>
                <% is_me = pid == @current_user_id %>
                <% is_creator = pid == @lobby.creator_id %>
                <% has_voted = Map.has_key?(@lobby.votes, pid) %>
                <% vote_value = Map.get(@lobby.votes, pid) %>

                <div
                  id={"participant-#{pid}"}
                  class={[
                    "flex items-center gap-3 rounded-xl px-4 py-3 border transition-colors",
                    if(is_me,
                      do: "bg-primary/5 border-primary/20",
                      else: "bg-base-200 border-base-300"
                    )
                  ]}
                >
                  <%!-- Avatar + presence indicator --%>
                  <div class="relative flex-shrink-0">
                    <span class="text-2xl">{participant.avatar}</span>
                    <span class={[
                      "absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full border-2 border-base-100",
                      if(presence_meta && presence_meta.status == :reading,
                        do: "bg-warning",
                        else: "bg-success"
                      )
                    ]}>
                    </span>
                  </div>

                  <%!-- Name + badges --%>
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-1.5">
                      <span class="text-sm font-medium text-base-content truncate">
                        {participant.name}
                      </span>
                      <%= if is_creator do %>
                        <span class="text-[10px] bg-base-300 text-base-content/50 px-1.5 py-0.5 rounded font-medium uppercase tracking-wide">
                          host
                        </span>
                      <% end %>
                      <%= if is_me do %>
                        <span class="text-[10px] bg-primary/20 text-primary px-1.5 py-0.5 rounded font-medium uppercase tracking-wide">
                          you
                        </span>
                      <% end %>
                    </div>
                  </div>

                  <%!-- Vote status --%>
                  <div class="flex-shrink-0">
                    <%= cond do %>
                      <% @lobby.state == :voting && has_voted -> %>
                        <div class="w-8 h-11 rounded bg-primary/20 border-2 border-primary/40 flex items-center justify-center">
                          <.icon name="hero-check-micro" class="size-3 text-primary" />
                        </div>
                      <% @lobby.state == :voting && not has_voted -> %>
                        <div class="w-8 h-11 rounded bg-base-300/50 border-2 border-base-300 flex items-center justify-center">
                          <span class="text-base-content/20 text-xs">?</span>
                        </div>
                      <% @lobby.state == :revealed && vote_value -> %>
                        <div class="w-8 h-11 rounded bg-base-100 border-2 border-base-300 flex items-center justify-center font-bold text-sm text-base-content">
                          {vote_value}
                        </div>
                      <% true -> %>
                        <div class="w-8 h-11"></div>
                    <% end %>
                  </div>

                  <%!-- Emoji throw + kick (hover actions) --%>
                  <%= if not is_me do %>
                    <div class="hidden group-hover:flex items-center gap-1"></div>
                    <div class="dropdown dropdown-end">
                      <button
                        tabindex="0"
                        class="btn btn-ghost btn-xs text-base-content/30 hover:text-base-content"
                      >
                        <.icon name="hero-face-smile-micro" class="size-4" />
                      </button>
                      <div
                        tabindex="0"
                        class="dropdown-content z-10 bg-base-100 border border-base-300 rounded-xl p-2 shadow-lg w-52"
                      >
                        <p class="text-xs text-base-content/50 mb-2 px-1">Throw an emoji</p>
                        <div class="flex flex-wrap gap-1">
                          <%= for emoji <- @throw_emojis do %>
                            <button
                              phx-click="throw_emoji"
                              phx-value-to={pid}
                              phx-value-emoji={emoji}
                              class="text-xl w-8 h-8 rounded hover:bg-base-200 flex items-center justify-center transition-colors cursor-pointer"
                            >
                              {emoji}
                            </button>
                          <% end %>
                        </div>
                        <%= if @current_user_id == @lobby.creator_id do %>
                          <div class="border-t border-base-300 mt-2 pt-2">
                            <button
                              phx-click="kick"
                              phx-value-user-id={pid}
                              class="w-full text-left text-xs text-error hover:bg-error/10 rounded px-2 py-1 transition-colors cursor-pointer"
                            >
                              Remove from lobby
                            </button>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".EmojiThrow">
      export default {
        mounted() {
          this.handleEvent("emoji_thrown", ({ from, to, emoji, target_el }) => {
            const fromEl = document.getElementById(`participant-${from}`)
            const toEl = document.getElementById(target_el)
            if (!fromEl || !toEl) return

            const fromRect = fromEl.getBoundingClientRect()
            const toRect = toEl.getBoundingClientRect()

            const el = document.createElement("div")
            el.textContent = emoji
            el.style.cssText = [
              "position:fixed",
              `left:${fromRect.left + fromRect.width / 2}px`,
              `top:${fromRect.top + fromRect.height / 2}px`,
              "font-size:2rem",
              "pointer-events:none",
              "z-index:9999",
              "transform:translate(-50%,-50%)",
              "transition:left 0.8s ease-in-out, top 0.8s ease-in-out, opacity 0.2s ease 0.7s",
              "will-change:left,top,opacity"
            ].join(";")

            document.body.appendChild(el)

            requestAnimationFrame(() => {
              requestAnimationFrame(() => {
                el.style.left = `${toRect.left + toRect.width / 2}px`
                el.style.top = `${toRect.top + toRect.height / 2}px`
                el.style.opacity = "0"
              })
            })

            setTimeout(() => el.remove(), 1100)
          })
        }
      }
    </script>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp get_presence_meta(presence, user_id) do
    case Map.get(presence, user_id) do
      %{metas: [meta | _]} -> meta
      _ -> nil
    end
  end

  defp nilify(""), do: nil
  defp nilify(val), do: val

  defp generate_id do
    :crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false)
  end
end
