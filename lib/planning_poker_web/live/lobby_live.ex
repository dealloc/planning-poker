defmodule PlanningPokerWeb.LobbyLive do
  use PlanningPokerWeb, :live_view

  alias PlanningPoker.{LobbyServer, Presence}

  @throw_emojis [
    # Reactions
    "👍", "👎", "🎉", "❤️", "😂", "🤔", "🔥", "💩", "🚀", "⭐",
    # More reactions
    "😍", "😅", "🥲", "😬", "🤯", "🤩", "😤", "🥳", "😴", "🤦",
    # Work & process
    "✅", "❌", "⚠️", "🐛", "🔑", "💡", "📦", "🧪", "🛑", "📝",
    # Team & fun
    "🙌", "👀", "🤝", "💪", "🎯", "🏆", "🍕", "☕", "🎲", "🐢"
  ]

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
              |> assign(:pending_host_transfer, lobby.pending_host_transfer)
              |> assign(:elapsed_seconds, elapsed_seconds(lobby.opened_at))
              |> assign(:editing_note_id, nil)
              |> assign(:show_qr_modal, false)
              |> assign(:qr_svg, nil)

            if connected?(socket), do: Process.send_after(self(), :tick, 1_000)

            {:ok, socket}

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(
               :error,
               "This lobby no longer exists — it may have ended or the link is no longer valid."
             )
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

  def handle_event("reorder_queue", %{"ids" => ids}, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns

    if uid == lobby.creator_id do
      LobbyServer.reorder_queue(lobby.id, uid, ids)
    end

    {:noreply, socket}
  end

  def handle_event("toggle_auto_reveal", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.toggle_auto_reveal(lobby.id, uid)
    # lobby.auto_reveal reflects the state *before* the toggle, so we negate it for the message
    {:noreply,
     socket
     |> put_flash(:info, "Auto-reveal #{if lobby.auto_reveal, do: "disabled", else: "enabled"}")}
  end

  def handle_event("toggle_members_queue", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.toggle_members_queue(lobby.id, uid)

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Members can add to queue: #{if lobby.members_can_add_to_queue, do: "disabled", else: "enabled"}"
     )}
  end

  def handle_event("kick", %{"user-id" => user_id}, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.kick(lobby.id, uid, user_id)
    {:noreply, socket}
  end

  def handle_event("transfer_host", %{"user-id" => to_id}, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.transfer_host(lobby.id, uid, to_id)
    {:noreply, socket}
  end

  def handle_event("accept_host_transfer", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.accept_host_transfer(lobby.id, uid)
    {:noreply, assign(socket, :pending_host_transfer, nil)}
  end

  def handle_event("decline_host_transfer", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    LobbyServer.decline_host_transfer(lobby.id, uid)
    {:noreply, assign(socket, :pending_host_transfer, nil)}
  end

  def handle_event("export_history", %{"format" => format}, socket) do
    history = socket.assigns.lobby.history
    date = Date.utc_today() |> Date.to_iso8601()
    filename = "planning-poker-history-#{date}"

    case format do
      "csv" ->
        content = build_csv(history)

        {:noreply,
         push_event(socket, "download_file", %{
           filename: "#{filename}.csv",
           content: content,
           mime_type: "text/csv"
         })}

      "json" ->
        content = build_json(history)

        {:noreply,
         push_event(socket, "download_file", %{
           filename: "#{filename}.json",
           content: content,
           mime_type: "application/json"
         })}

      "markdown" ->
        content = build_markdown(history)

        {:noreply,
         push_event(socket, "download_file", %{
           filename: "#{filename}.md",
           content: content,
           mime_type: "text/markdown"
         })}

      _ ->
        {:noreply, socket}
    end
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

  def handle_event("copy_lobby_link", _params, socket) do
    lobby_url = url(~p"/lobby/#{socket.assigns.lobby.id}")
    {:noreply, push_event(socket, "copy_to_clipboard", %{text: lobby_url})}
  end

  def handle_event("toggle_spectator", _params, socket) do
    %{lobby: lobby, current_user_id: uid} = socket.assigns
    participant = Map.get(lobby.participants, uid)
    currently_spectating = participant && participant.role == :spectator
    LobbyServer.set_spectator(lobby.id, uid, not currently_spectating)
    {:noreply, socket}
  end

  def handle_event("edit_note", %{"id" => item_id}, socket) do
    {:noreply, assign(socket, :editing_note_id, item_id)}
  end

  def handle_event("cancel_note", _params, socket) do
    {:noreply, assign(socket, :editing_note_id, nil)}
  end

  def handle_event("save_note", %{"item_id" => item_id, "note" => note}, socket) do
    %{lobby: lobby} = socket.assigns
    note_value = if String.trim(note) == "", do: nil, else: String.trim(note)
    LobbyServer.update_history_note(lobby.id, item_id, note_value)
    {:noreply, assign(socket, :editing_note_id, nil)}
  end

  def handle_event("show_qr_code", _params, socket) do
    lobby_url = url(~p"/lobby/#{socket.assigns.lobby.id}")
    {:ok, svg} = lobby_url
      |> QRCode.create(:medium)
      |> QRCode.render(:svg, %QRCode.Render.SvgSettings{scale: 5})
    {:noreply, assign(socket, show_qr_modal: true, qr_svg: svg)}
  end

  def handle_event("close_qr_modal", _params, socket) do
    {:noreply, assign(socket, show_qr_modal: false)}
  end

  # ── PubSub messages ──────────────────────────────────────────────────────────

  @impl true
  def handle_info({:lobby_updated, lobby}, socket) do
    my_vote = Map.get(lobby.votes, socket.assigns.current_user_id)

    # Keep local pending_host_transfer unless it was cleared server-side
    pending =
      if lobby.pending_host_transfer == nil do
        nil
      else
        socket.assigns.pending_host_transfer
      end

    {:noreply,
     socket
     |> assign(:lobby, lobby)
     |> assign(:my_vote, my_vote)
     |> assign(:pending_host_transfer, pending)}
  end

  def handle_info({:host_transfer_offered, to_id}, socket) do
    lobby = %{socket.assigns.lobby | pending_host_transfer: to_id}
    socket = assign(socket, :lobby, lobby)

    socket =
      if socket.assigns.current_user_id == to_id do
        assign(socket, :pending_host_transfer, to_id)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:host_transfer_declined, _user_id}, socket) do
    lobby = %{socket.assigns.lobby | pending_host_transfer: nil}
    {:noreply, socket |> assign(:lobby, lobby) |> assign(:pending_host_transfer, nil)}
  end

  def handle_info(:tick, socket) do
    elapsed = elapsed_seconds(socket.assigns.lobby.opened_at)
    Process.send_after(self(), :tick, 1_000)
    {:noreply, assign(socket, :elapsed_seconds, elapsed)}
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
        id="keyboard-shortcuts-root"
        phx-hook=".KeyboardShortcuts"
        data-state={@lobby.state}
        data-is-creator={to_string(@current_user_id == @lobby.creator_id)}
        data-planning-system={@lobby.planning_system}
        data-queue-empty={to_string(@lobby.queue == [])}
        style="display:none"
        aria-hidden="true"
      >
      </div>
      <div
        id="lobby-root"
        phx-window-blur="blur"
        phx-window-focus="focus"
        phx-hook=".EmojiThrow"
        class="pb-12"
      >
        <%!-- Host transfer offer banner (only visible to the invited user) --%>
        <%= if @pending_host_transfer == @current_user_id do %>
          <% offerer = Map.get(@lobby.participants, @lobby.creator_id) %>
          <div class="mb-4 flex items-center justify-between gap-4 rounded-xl border border-primary/30 bg-primary/10 px-4 py-3">
            <div class="flex items-center gap-2 text-sm text-base-content">
              <.icon name="hero-crown-micro" class="size-4 text-primary flex-shrink-0" />
              <span>
                <span class="font-semibold">
                  {if offerer, do: offerer.name, else: "The host"}
                </span>
                wants to make you the host of this lobby.
              </span>
            </div>
            <div class="flex items-center gap-2 flex-shrink-0">
              <button
                phx-click="accept_host_transfer"
                class="flex items-center gap-1.5 bg-primary text-primary-content rounded-lg px-3 py-1.5 text-sm font-medium hover:bg-primary/90 transition-colors cursor-pointer"
              >
                Accept
              </button>
              <button
                phx-click="decline_host_transfer"
                class="flex items-center gap-1.5 bg-base-200 border border-base-300 rounded-lg px-3 py-1.5 text-sm text-base-content/60 hover:bg-base-300 transition-colors cursor-pointer"
              >
                Decline
              </button>
            </div>
          </div>
        <% end %>
        <%!-- Header --%>
        <div class="flex flex-wrap items-center justify-between gap-4 py-4 sm:py-6 border-b border-base-300 mb-5 sm:mb-8">
          <div>
            <h1 class="text-xl sm:text-2xl font-bold text-base-content">{@lobby.name}</h1>
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

              <%!-- Live vote progress counter --%>
              <%= if @lobby.state == :voting do %>
                <% voter_count = Enum.count(@lobby.participants, fn {_id, p} -> p.role == :voter end) %>
                <span class="text-xs text-base-content/50">
                  {map_size(@lobby.votes)}/{voter_count} voted
                </span>
              <% end %>

              <%!-- Elapsed timer --%>
              <span class="text-xs text-base-content/40">
                {format_elapsed(@elapsed_seconds)}
              </span>
            </div>
          </div>

          <div class="flex items-center gap-2 sm:gap-3 flex-wrap justify-end">
            <%!-- Creator-only toggles --%>
            <%= if @current_user_id == @lobby.creator_id do %>
              <button
                id="toggle-auto-reveal"
                phx-click="toggle_auto_reveal"
                title="When ON: votes reveal automatically once everyone has voted. When OFF: you choose when to reveal."
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
              <button
                id="toggle-members-queue"
                phx-click="toggle_members_queue"
                title="When ON: all members can add items to the queue. When OFF: only the host can."
                class={[
                  "flex items-center gap-2 text-sm px-3 py-1.5 rounded-lg border transition-colors cursor-pointer",
                  if(@lobby.members_can_add_to_queue,
                    do: "bg-primary/10 border-primary/30 text-primary",
                    else: "bg-base-200 border-base-300 text-base-content/60 hover:border-base-400"
                  )
                ]}
              >
                <.icon name="hero-queue-list-micro" class="size-3.5" /> Member queue
              </button>
            <% end %>

            <%!-- Share link --%>
            <button
              phx-click="copy_lobby_link"
              class="flex items-center gap-1.5 bg-base-200 border border-base-300 rounded-lg px-3 py-1.5 hover:bg-base-300 transition-colors cursor-pointer"
              title="Click to copy invite link"
            >
              <.icon name="hero-link-micro" class="size-3.5 text-base-content/50" />
              <span class="text-xs font-mono text-base-content/60 hidden sm:inline">
                {~p"/lobby/#{@lobby.id}"}
              </span>
              <span class="text-xs font-medium text-base-content/60 sm:hidden">Copy link</span>
            </button>
            <button
              phx-click="show_qr_code"
              class="flex items-center gap-1.5 bg-base-200 border border-base-300 rounded-lg px-3 py-1.5 hover:bg-base-300 transition-colors cursor-pointer"
              title="Show QR code for this lobby"
              aria-label="Show QR code"
            >
              <.icon name="hero-qr-code-micro" class="size-3.5 text-base-content/50" />
              <span class="text-xs font-medium text-base-content/60 hidden sm:inline">QR</span>
            </button>
            <button
              onclick="document.getElementById('shortcuts-modal').classList.toggle('hidden')"
              class="flex items-center gap-1.5 bg-base-200 border border-base-300 rounded-lg px-3 py-1.5 hover:bg-base-300 transition-colors cursor-pointer"
              title="Keyboard shortcuts (?)"
              aria-label="Keyboard shortcuts"
            >
              <kbd class="kbd kbd-sm text-xs">?</kbd>
            </button>
          </div>
        </div>

        <%!-- Main layout: voting area + participants --%>
        <div class="grid grid-cols-1 lg:grid-cols-[1fr_280px] gap-6 lg:gap-8">
          <%!-- Left: Voting area --%>
          <div class="order-2 lg:order-1">
            <%!-- Current item --%>
            <%= if @lobby.current_item do %>
              <div class="bg-base-200 rounded-xl p-6 mb-6 border border-base-300">
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <p class="text-xs text-base-content/50 uppercase tracking-wider font-medium mb-1">
                      Current item
                    </p>
                    <h2 class="text-2xl font-bold text-base-content">
                      {@lobby.current_item.title}
                    </h2>
                    <%= if @lobby.current_item.context_url do %>
                      <a
                        href={@lobby.current_item.context_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center gap-2 mt-2 px-3 py-2 rounded-lg bg-primary/10 border border-primary/30 text-primary text-sm font-medium hover:bg-primary/20 hover:border-primary/50 transition-colors"
                      >
                        <.icon name="hero-arrow-top-right-on-square-micro" class="size-4" />
                        {URI.parse(@lobby.current_item.context_url).host || "View Context"}
                      </a>
                    <% end %>
                  </div>

                  <%!-- Creator actions during voting/revealed --%>
                  <%= if @current_user_id == @lobby.creator_id do %>
                    <div class="flex gap-2 flex-shrink-0">
                      <%= if @lobby.state == :voting do %>
                        <.button id="reveal-btn" phx-click="reveal" class="btn btn-sm btn-primary">
                          Reveal
                        </.button>
                      <% end %>
                      <%= if @lobby.state == :revealed do %>
                        <.button id="reset-btn" phx-click="reset_round" class="btn btn-sm btn-ghost">
                          Re-vote
                        </.button>
                        <%= if @lobby.queue != [] do %>
                          <.button
                            id="next-item-btn"
                            phx-click="next_item"
                            class="btn btn-sm btn-primary"
                          >
                            Next Item →
                          </.button>
                        <% end %>
                      <% end %>
                      <.button
                        id="skip-btn"
                        phx-click="skip_item"
                        class="btn btn-sm btn-ghost text-base-content/50"
                      >
                        Skip
                      </.button>
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
                <%= if stats.clarification_count > 0 do %>
                  <div class="flex items-center gap-2 mb-4 rounded-lg border border-warning/40 bg-warning/10 px-3 py-2 text-sm text-warning">
                    <.icon name="hero-question-mark-circle-micro" class="size-4 flex-shrink-0" />
                    {stats.clarification_count} participant{if stats.clarification_count == 1, do: "", else: "s"} requested clarification — discuss before re-voting.
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
                <% cards_ordered = PlanningPoker.Lobby.cards(@lobby.planning_system) %>
                <div class="flex flex-wrap gap-2">
                  <%= for {card, count} <- Enum.sort_by(stats.distribution, fn {k, _} ->
                        Enum.find_index(cards_ordered, &(&1 == k)) || 9999
                      end) do %>
                    <% tier = vote_tier(card, cards_ordered, stats.median) %>
                    <div class={[
                      "flex items-center gap-1.5 rounded-lg border px-3 py-1.5",
                      tier == :outlier && "bg-error/15 border-error/40",
                      tier == :near_consensus && "bg-success/15 border-success/40",
                      tier == :middle && "bg-base-100 border-base-300",
                      tier == :clarification && "bg-warning/15 border-warning/40"
                    ]}>
                      <span class={[
                        "font-mono font-semibold",
                        tier == :outlier && "text-error",
                        tier == :near_consensus && "text-success",
                        tier == :middle && "text-base-content",
                        tier == :clarification && "text-warning"
                      ]}>
                        {card}
                      </span>
                      <span class={[
                        "text-xs",
                        tier == :outlier && "text-error/70",
                        tier == :near_consensus && "text-success/70",
                        tier == :middle && "text-base-content/50",
                        tier == :clarification && "text-warning/70"
                      ]}>
                        ×{count}
                      </span>
                    </div>
                  <% end %>
                </div>

                <%!-- Bar chart --%>
                <%= if map_size(stats.distribution) > 0 do %>
                  <% max_count = stats.distribution |> Map.values() |> Enum.max() %>
                  <div class="mt-5">
                    <p class="text-xs text-base-content/40 uppercase tracking-wider mb-2">
                      Distribution
                    </p>
                    <div class="flex items-end gap-2 h-28 border-b border-base-300">
                      <%= for card <- cards_ordered,
                              count = Map.get(stats.distribution, card),
                              count != nil do %>
                        <% tier = vote_tier(card, cards_ordered, stats.median) %>
                        <div class="flex flex-col items-center gap-1 flex-1 min-w-[2rem]">
                          <span class="text-[10px] text-base-content/50 leading-none">{count}</span>
                          <div
                            class={[
                              "w-full rounded-t-md transition-all",
                              tier == :outlier && "bg-error/60",
                              tier == :near_consensus && "bg-success/60",
                              tier == :middle && "bg-primary/40",
                              tier == :clarification && "bg-warning/60"
                            ]}
                            style={"height: #{Float.round(count / max_count * 100, 1)}%;"}
                          >
                          </div>
                        </div>
                      <% end %>
                    </div>
                    <div class="flex gap-2 mt-1">
                      <%= for card <- cards_ordered, Map.has_key?(stats.distribution, card) do %>
                        <div class="flex-1 min-w-[2rem] text-center text-[10px] text-base-content/40 font-mono truncate">
                          {card}
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%!-- Voting cards --%>
            <%= if @lobby.state == :voting do %>
              <% me = Map.get(@lobby.participants, @current_user_id) %>
              <% is_spectator = me && me.role == :spectator %>
              <%= if is_spectator do %>
                <div class="mb-6 flex flex-col items-center justify-center py-8 text-center rounded-xl border border-base-300 bg-base-200">
                  <.icon name="hero-eye-micro" class="size-8 text-base-content/30 mb-3" />
                  <p class="text-base font-medium text-base-content/50">You are watching this round</p>
                  <p class="text-sm text-base-content/40 mt-1">Toggle spectator mode to vote</p>
                </div>
              <% else %>
              <% cards = PlanningPoker.Lobby.cards(@lobby.planning_system) %>
              <div class="mb-6">
                <div class="grid grid-cols-4 sm:grid-cols-6 md:flex md:flex-wrap gap-3">
                  <%= for card <- cards do %>
                    <% selected = @my_vote == card %>
                    <button
                      id={"card-#{card}"}
                      phx-click="vote"
                      phx-value-card={card}
                      class={[
                        "relative h-24 sm:h-28 md:w-20 rounded-xl border-2 text-xl font-bold",
                        "flex flex-col items-center justify-center cursor-pointer select-none",
                        "transition-all duration-150 hover:-translate-y-1 hover:scale-110 hover:shadow-lg",
                        if(selected,
                          do:
                            "bg-primary text-primary-content border-primary shadow-lg -translate-y-2 scale-105 card-select-glow",
                          else:
                            if(card == "?",
                              do: "bg-warning/10 border-warning/40 text-warning hover:border-warning/70",
                              else: "bg-base-200 border-base-300 text-base-content hover:border-primary/50"
                            )
                        )
                      ]}
                    >
                      {card}
                      <%= if selected do %>
                        <span class="absolute bottom-1.5 left-0 right-0 mx-auto flex items-center justify-center gap-0.5 text-[9px] font-semibold uppercase tracking-widest leading-none text-primary-content/80">
                          <svg
                            class="size-2.5 shrink-0"
                            viewBox="0 0 12 12"
                            fill="none"
                            xmlns="http://www.w3.org/2000/svg"
                            aria-hidden="true"
                          >
                            <path
                              d="M2 6.5L4.8 9.5L10 3"
                              stroke="currentColor"
                              stroke-width="1.8"
                              stroke-linecap="round"
                              stroke-linejoin="round"
                            />
                          </svg>
                          Picked
                        </span>
                      <% end %>
                    </button>
                  <% end %>
                </div>
                <p class="text-sm text-base-content/60 mt-3 text-center">
                  <%= if @my_vote do %>
                    You voted
                    <span class="font-mono font-bold bg-primary/20 px-1.5 py-0.5 rounded">
                      {@my_vote}
                    </span>
                    — tap another card to change your vote.
                  <% else %>
                    Pick your estimate. You can change it anytime before reveal.
                  <% end %>
                </p>
              </div>
              <% end %>
            <% end %>

            <%!-- Waiting state: creator controls --%>
            <%= if @lobby.state == :waiting && @current_user_id == @lobby.creator_id do %>
              <div class="space-y-4">
                <%!-- Start item inline --%>
                <%= if not @show_start_form do %>
                  <div class="bg-base-100 border-2 border-primary/20 rounded-xl p-6">
                    <h3 class="text-base font-semibold mb-1">Ready to estimate?</h3>
                    <p class="text-sm text-base-content/60 mb-4">
                      Start a new item to begin voting, or select the next one from your queue.
                    </p>
                    <div class="flex gap-3">
                      <.button
                        id="start-item-toggle"
                        phx-click="toggle_start_form"
                        class="btn btn-primary"
                      >
                        <.icon name="hero-play-micro" class="size-4" /> Start item
                      </.button>
                      <%= if @lobby.queue != [] do %>
                        <.button id="next-from-queue-btn" phx-click="next_item" class="btn btn-ghost">
                          Next from queue ({length(@lobby.queue)})
                        </.button>
                      <% end %>
                    </div>
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
                        <.button type="submit" class="btn btn-primary btn-sm">Start voting</.button>
                        <.button
                          type="button"
                          phx-click="toggle_start_form"
                          class="btn btn-ghost btn-sm"
                        >
                          Cancel
                        </.button>
                      </div>
                    </.form>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%!-- Waiting state, non-creator --%>
            <%= if @lobby.state == :waiting && @current_user_id != @lobby.creator_id do %>
              <% facilitator = Map.get(@lobby.participants, @lobby.creator_id) %>
              <div class="flex flex-col items-center justify-center py-12 text-center">
                <div class="text-5xl mb-4">⏳</div>
                <p class="text-lg font-medium text-base-content/60">
                  Waiting for
                  <%= if facilitator do %>
                    <span class="text-base-content/80 font-semibold">{facilitator.name}</span>
                  <% else %>
                    the facilitator
                  <% end %>
                  to start a round…
                </p>
                <p class="text-sm text-base-content/40 mt-2">
                  You'll be able to vote once a story or task is started.
                </p>
              </div>
              <%!-- Queue progress for non-creator members (waiting state) --%>
              <%= if @lobby.queue != [] || @lobby.history != [] || @lobby.members_can_add_to_queue do %>
                <.queue_progress_panel
                  lobby={@lobby}
                  show_queue_form={@show_queue_form}
                  queue_form={@queue_form}
                />
              <% end %>
            <% end %>

            <%!-- Queue progress for non-creator members (voting/revealed state) --%>
            <%= if @current_user_id != @lobby.creator_id && @lobby.state != :waiting && (@lobby.queue != [] || @lobby.history != [] || @lobby.members_can_add_to_queue) do %>
              <.queue_progress_panel
                lobby={@lobby}
                show_queue_form={@show_queue_form}
                queue_form={@queue_form}
              />
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
                  <.button
                    id="toggle-queue-form"
                    phx-click="toggle_queue_form"
                    class="btn btn-ghost btn-xs"
                  >
                    <.icon name="hero-plus-micro" class="size-3.5" /> Add
                  </.button>
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
                        <.button type="submit" class="btn btn-primary btn-sm">Add to queue</.button>
                        <.button
                          type="button"
                          phx-click="toggle_queue_form"
                          class="btn btn-ghost btn-sm"
                        >
                          Cancel
                        </.button>
                      </div>
                    </.form>
                  </div>
                <% end %>

                <%= if @lobby.queue == [] && not @show_queue_form do %>
                  <p class="text-sm text-base-content/40 py-3 text-center">
                    No items queued yet.
                    <button phx-click="toggle_queue_form" class="link link-primary">
                      Add a story
                    </button>
                  </p>
                <% end %>

                <div
                  id="queue-list"
                  phx-hook=".QueueSortable"
                  class="space-y-2"
                >
                  <%= for {item, index} <- Enum.with_index(@lobby.queue) do %>
                    <div
                      id={"queue-item-#{item.id}"}
                      data-id={item.id}
                      class="flex items-center gap-3 bg-base-200 rounded-lg px-4 py-2.5 border border-base-300 group"
                    >
                      <span class="drag-handle cursor-grab text-base-content/30 hover:text-base-content/60 shrink-0">
                        <.icon name="hero-bars-2-micro" class="size-4" />
                      </span>
                      <span class="text-xs text-base-content/40 font-mono tabular-nums w-4 shrink-0">
                        {index + 1}.
                      </span>
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
                <div class="flex items-center justify-between mb-4">
                  <h3 class="font-semibold text-base-content/80">History</h3>
                  <div class="flex items-center gap-2">
                    <button
                      phx-click="export_history"
                      phx-value-format="csv"
                      class="flex items-center gap-1.5 bg-base-200 border border-base-300 rounded-lg px-3 py-1.5 hover:bg-base-300 transition-colors cursor-pointer text-xs font-medium text-base-content/70"
                    >
                      <.icon name="hero-arrow-down-tray-micro" class="size-3.5 text-base-content/50" />
                      Export CSV
                    </button>
                    <button
                      phx-click="export_history"
                      phx-value-format="json"
                      class="flex items-center gap-1.5 bg-base-200 border border-base-300 rounded-lg px-3 py-1.5 hover:bg-base-300 transition-colors cursor-pointer text-xs font-medium text-base-content/70"
                    >
                      <.icon name="hero-arrow-down-tray-micro" class="size-3.5 text-base-content/50" />
                      Export JSON
                    </button>
                    <button
                      phx-click="export_history"
                      phx-value-format="markdown"
                      class="flex items-center gap-1.5 bg-base-200 border border-base-300 rounded-lg px-3 py-1.5 hover:bg-base-300 transition-colors cursor-pointer text-xs font-medium text-base-content/70"
                    >
                      <.icon name="hero-arrow-down-tray-micro" class="size-3.5 text-base-content/50" />
                      Export Markdown
                    </button>
                  </div>
                </div>
                <div class="space-y-3">
                  <%= for entry <- @lobby.history do %>
                    <% entry_item_id = entry.item && entry.item.id %>
                    <% is_editing_note = @editing_note_id == entry_item_id %>
                    <div
                      id={"history-#{entry_item_id}"}
                      class="bg-base-200 rounded-xl px-5 py-4 border border-base-300"
                    >
                      <div class="flex items-center justify-between gap-4">
                        <span class="text-sm font-medium text-base-content">
                          {entry.item && entry.item.title}
                        </span>
                        <div class="flex items-center gap-3 flex-shrink-0">
                          <%= if formatted = format_duration(entry[:duration_seconds]) do %>
                            <span class="text-xs text-base-content/40 font-mono">
                              {formatted}
                            </span>
                          <% end %>
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
                          <%= if not is_editing_note do %>
                            <button
                              phx-click="edit_note"
                              phx-value-id={entry_item_id}
                              class="text-base-content/30 hover:text-base-content/60 transition-colors cursor-pointer"
                              title="Add note"
                              aria-label="Add note"
                            >
                              <.icon name="hero-pencil-square-micro" class="size-3.5" />
                            </button>
                          <% end %>
                        </div>
                      </div>
                      <%!-- Note display / edit --%>
                      <%= if is_editing_note do %>
                        <form phx-submit="save_note" class="mt-3">
                          <input type="hidden" name="item_id" value={entry_item_id} />
                          <textarea
                            name="note"
                            rows="2"
                            placeholder="Add a note for this item…"
                            class="w-full text-sm rounded-lg border border-base-300 bg-base-100 px-3 py-2 resize-none focus:outline-none focus:border-primary/50"
                            autofocus
                          >{entry[:note]}</textarea>
                          <div class="flex gap-2 mt-2">
                            <button type="submit" class="btn btn-primary btn-xs">Save</button>
                            <button type="button" phx-click="cancel_note" class="btn btn-ghost btn-xs">Cancel</button>
                          </div>
                        </form>
                      <% else %>
                        <%= if entry[:note] do %>
                          <p class="mt-2 text-xs text-base-content/60 italic border-l-2 border-base-300 pl-2">
                            {entry[:note]}
                          </p>
                        <% end %>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
              <.session_stats_panel history={@lobby.history} opened_at={@lobby.opened_at} />
            <% end %>
          </div>

          <%!-- Right: Participant list --%>
          <div class="order-1 lg:order-2">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-3">
              Participants ({map_size(@lobby.participants)})
            </h3>
            <div class="flex items-center gap-4 mb-4 text-xs text-base-content/50">
              <span class="flex items-center gap-1.5">
                <span class="size-3 rounded-full bg-success inline-block"></span> Ready
              </span>
              <span class="flex items-center gap-1.5">
                <span class="size-3 rounded-full bg-warning inline-block"></span> Away
              </span>
            </div>

            <div class="space-y-2">
              <%= for {pid, participant} <- @lobby.participants do %>
                <% presence_meta = get_presence_meta(@presence, pid) %>
                <% is_me = pid == @current_user_id %>
                <% is_creator = pid == @lobby.creator_id %>
                <% is_spectator = participant.role == :spectator %>
                <% has_voted = Map.has_key?(@lobby.votes, pid) %>
                <% vote_value = Map.get(@lobby.votes, pid) %>

                <div
                  id={"participant-#{pid}"}
                  class={[
                    "flex items-center gap-2 sm:gap-3 rounded-xl px-3 sm:px-4 py-2.5 sm:py-3 border transition-colors",
                    if(is_me,
                      do: "bg-primary/5 border-primary/20",
                      else: "bg-base-200 border-base-300"
                    )
                  ]}
                >
                  <%!-- Avatar + presence indicator --%>
                  <div class="relative flex-shrink-0">
                    <span class="text-2xl">{participant.avatar}</span>
                    <span
                      title={
                        if(presence_meta && presence_meta.status == :reading,
                          do: "Away",
                          else: "Ready"
                        )
                      }
                      aria-label={
                        if(presence_meta && presence_meta.status == :reading,
                          do: "Away",
                          else: "Ready"
                        )
                      }
                      class={[
                        "absolute -bottom-0.5 -right-0.5 size-3 rounded-full border-2 border-base-100",
                        if(presence_meta && presence_meta.status == :reading,
                          do: "bg-warning",
                          else: "bg-success"
                        )
                      ]}
                    >
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
                      <%= if is_spectator do %>
                        <span class="text-[10px] bg-base-300 text-base-content/40 px-1.5 py-0.5 rounded font-medium uppercase tracking-wide flex items-center gap-0.5">
                          <.icon name="hero-eye-micro" class="size-2.5" /> watching
                        </span>
                      <% end %>
                    </div>
                  </div>

                  <%!-- Vote status --%>
                  <div class="flex-shrink-0">
                    <%= cond do %>
                      <% is_spectator -> %>
                        <div class="w-8 h-11"></div>
                      <% @lobby.state == :voting && has_voted -> %>
                        <div class="w-8 h-11 rounded bg-primary/20 border-2 border-primary/40 flex items-center justify-center">
                          <.icon name="hero-check-micro" class="size-3 text-primary" />
                        </div>
                      <% @lobby.state == :voting && not has_voted -> %>
                        <div class="w-8 h-11 rounded bg-base-300/50 border-2 border-base-300 flex items-center justify-center">
                          <span class="text-base-content/20 text-xs">?</span>
                        </div>
                      <% @lobby.state == :revealed && vote_value == "?" -> %>
                        <div class="w-8 h-11 rounded bg-warning/15 border-2 border-warning/40 flex items-center justify-center font-bold text-sm text-warning">
                          {vote_value}
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
                      <.button
                        tabindex="0"
                        class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px] sm:min-h-0 sm:min-w-0 text-base-content/30 hover:text-base-content"
                      >
                        <.icon name="hero-face-smile-micro" class="size-4" />
                      </.button>
                      <div
                        tabindex="0"
                        class="dropdown-content z-10 bg-base-100 border border-base-300 rounded-xl p-2 shadow-lg w-72"
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
                          <div class="border-t border-base-300 mt-2 pt-2 space-y-0.5">
                            <button
                              phx-click="transfer_host"
                              phx-value-user-id={pid}
                              class="w-full text-left text-xs text-base-content/60 hover:bg-base-200 rounded px-2 py-2.5 sm:py-1 transition-colors cursor-pointer"
                            >
                              Make host
                            </button>
                            <button
                              phx-click="kick"
                              phx-value-user-id={pid}
                              class="w-full text-left text-xs text-error hover:bg-error/10 rounded px-2 py-2.5 sm:py-1 transition-colors cursor-pointer"
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

            <%!-- Spectator toggle button --%>
            <% me = Map.get(@lobby.participants, @current_user_id) %>
            <% i_am_spectator = me && me.role == :spectator %>
            <div class="mt-3">
              <button
                phx-click="toggle_spectator"
                class={[
                  "w-full flex items-center justify-center gap-2 text-xs rounded-lg px-3 py-2 border transition-colors cursor-pointer",
                  if(i_am_spectator,
                    do: "bg-base-300 border-base-400 text-base-content/70 hover:bg-base-200",
                    else: "bg-base-200 border-base-300 text-base-content/50 hover:bg-base-300"
                  )
                ]}
              >
                <.icon name="hero-eye-micro" class="size-3.5" />
                {if i_am_spectator, do: "Stop watching (join voting)", else: "Watch only (spectate)"}
              </button>
            </div>
          </div>
        </div>
      </div>
      <%!-- QR Code Modal --%>
      <%= if @show_qr_modal do %>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm"
          phx-click="close_qr_modal"
        >
          <div class="bg-base-100 rounded-2xl shadow-2xl border border-base-300 p-6 w-full max-w-xs mx-4" onclick="event.stopPropagation()">
            <div class="flex items-center justify-between mb-5">
              <h2 class="text-lg font-bold text-base-content">Join via QR Code</h2>
              <button phx-click="close_qr_modal" class="btn btn-ghost btn-sm btn-circle" aria-label="Close">
                <.icon name="hero-x-mark-micro" class="size-4" />
              </button>
            </div>
            <div class="flex flex-col items-center gap-4">
              <div class="rounded-lg overflow-hidden bg-white p-2 w-48 h-48 flex items-center justify-center [&>svg]:max-w-full [&>svg]:h-auto">
                <%= Phoenix.HTML.raw(@qr_svg) %>
              </div>
              <p class="text-xs font-mono text-base-content/60 break-all text-center select-all">
                {url(~p"/lobby/#{@lobby.id}")}
              </p>
            </div>
          </div>
        </div>
      <% end %>
      <%!-- Keyboard Shortcuts Modal --%>
      <div
        id="shortcuts-modal"
        phx-update="ignore"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm hidden"
        onclick="if(event.target===this) this.classList.add('hidden')"
      >
        <div class="bg-base-100 rounded-2xl shadow-2xl border border-base-300 p-6 w-full max-w-sm mx-4">
          <div class="flex items-center justify-between mb-5">
            <h2 class="text-lg font-bold text-base-content">Keyboard Shortcuts</h2>
            <button
              class="btn btn-ghost btn-sm btn-circle"
              onclick="document.getElementById('shortcuts-modal').classList.add('hidden')"
              aria-label="Close"
            >
              <.icon name="hero-x-mark-micro" class="size-4" />
            </button>
          </div>
          <div class="space-y-4 text-sm">
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wider font-medium mb-2">
                Voting
              </p>
              <div class="flex items-center justify-between">
                <span class="text-base-content/70">Vote for card (by position)</span>
                <div class="flex gap-1 flex-wrap justify-end">
                  <kbd class="kbd kbd-sm">1</kbd><span class="text-base-content/40">–</span><kbd class="kbd kbd-sm">9</kbd>
                  <kbd class="kbd kbd-sm">0</kbd><kbd class="kbd kbd-sm">Q</kbd><kbd class="kbd kbd-sm">W</kbd><kbd class="kbd kbd-sm">E</kbd>
                </div>
              </div>
            </div>
            <%= if @current_user_id == @lobby.creator_id do %>
              <div>
                <p class="text-xs text-base-content/50 uppercase tracking-wider font-medium mb-2">
                  Facilitator
                </p>
                <div class="space-y-1.5">
                  <div class="flex items-center justify-between">
                    <span class="text-base-content/70">Reveal votes</span>
                    <div class="flex gap-1">
                      <kbd class="kbd kbd-sm">Space</kbd><span class="text-base-content/40">or</span><kbd class="kbd kbd-sm">R</kbd>
                    </div>
                  </div>
                  <div class="flex items-center justify-between">
                    <span class="text-base-content/70">Re-vote</span>
                    <kbd class="kbd kbd-sm">V</kbd>
                  </div>
                  <div class="flex items-center justify-between">
                    <span class="text-base-content/70">Next item</span>
                    <kbd class="kbd kbd-sm">N</kbd>
                  </div>
                  <div class="flex items-center justify-between">
                    <span class="text-base-content/70">Toggle auto-reveal</span>
                    <kbd class="kbd kbd-sm">A</kbd>
                  </div>
                </div>
              </div>
            <% end %>
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wider font-medium mb-2">
                General
              </p>
              <div class="flex items-center justify-between">
                <span class="text-base-content/70">Toggle this help</span>
                <kbd class="kbd kbd-sm">?</kbd>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".EmojiThrow">
      export default {
        mounted() {
          this.handleEvent("download_file", ({ filename, content, mime_type }) => {
            const blob = new Blob([content], { type: mime_type })
            const url = URL.createObjectURL(blob)
            const a = document.createElement("a")
            a.href = url
            a.download = filename
            document.body.appendChild(a)
            a.click()
            document.body.removeChild(a)
            URL.revokeObjectURL(url)
          })

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

    <script :type={Phoenix.LiveView.ColocatedHook} name=".QueueSortable">
      export default {
        mounted() {
          this._sortable = new window.Sortable(this.el, {
            animation: 150,
            ghostClass: "opacity-40",
            handle: ".drag-handle",
            onEnd: ({ oldIndex, newIndex }) => {
              if (oldIndex === newIndex) return
              const ids = Array.from(this.el.children).map(el => el.dataset.id)
              this.pushEvent("reorder_queue", { ids })
            }
          })
        },
        updated() {},
        destroyed() {
          this._sortable.destroy()
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".KeyboardShortcuts">
      const VOTE_KEYS = ["1","2","3","4","5","6","7","8","9","0","q","w","e"]

      export default {
        mounted() {
          this._keydown = (e) => this.handleKey(e)
          window.addEventListener("keydown", this._keydown)
        },
        destroyed() {
          window.removeEventListener("keydown", this._keydown)
        },
        handleKey(e) {
          if (e.ctrlKey || e.altKey || e.metaKey) return
          const tag = document.activeElement?.tagName?.toLowerCase()
          if (tag === "input" || tag === "textarea" || tag === "select" || document.activeElement?.isContentEditable) return

          const key = e.key.toLowerCase()
          const ds = this.el.dataset
          const state = ds.state
          const isCreator = ds.isCreator === "true"
          const queueEmpty = ds.queueEmpty === "true"

          if (e.key === "?" || e.key === "/") {
            e.preventDefault()
            const modal = document.getElementById("shortcuts-modal")
            if (modal) modal.classList.toggle("hidden")
            return
          }

          if (e.key === "Escape") {
            const modal = document.getElementById("shortcuts-modal")
            if (modal && !modal.classList.contains("hidden")) {
              modal.classList.add("hidden")
              e.preventDefault()
            }
            return
          }

          if (state === "voting") {
            const idx = VOTE_KEYS.indexOf(key)
            if (idx !== -1) {
              e.preventDefault()
              const cardButtons = document.querySelectorAll("[id^='card-']")
              const btn = cardButtons[idx]
              if (btn) {
                const cardValue = btn.getAttribute("phx-value-card")
                if (cardValue) this.pushEvent("vote", {card: cardValue})
              }
              return
            }
          }

          if (!isCreator) return

          if ((key === " " || e.code === "Space" || key === "r") && state === "voting") {
            e.preventDefault()
            this.pushEvent("reveal", {})
            return
          }
          if (key === "v" && state === "revealed") {
            e.preventDefault()
            this.pushEvent("reset_round", {})
            return
          }
          if (key === "n" && state === "revealed" && !queueEmpty) {
            e.preventDefault()
            this.pushEvent("next_item", {})
            return
          }
          if (key === "a") {
            e.preventDefault()
            this.pushEvent("toggle_auto_reveal", {})
            return
          }
        }
      }
    </script>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  attr :history, :list, required: true
  attr :opened_at, :any, required: true

  defp session_stats_panel(assigns) do
    assigns = assign(assigns, :stats, session_stats(assigns.history, assigns.opened_at))
    ~H"""
    <%= if @stats.total_items > 0 do %>
      <div class="mt-6 bg-base-200 rounded-xl px-5 py-4 border border-base-300">
        <h3 class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-3">Session Stats</h3>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <div class="text-center">
            <div class="text-2xl font-bold text-base-content">{@stats.total_items}</div>
            <div class="text-xs text-base-content/50 mt-0.5">Items estimated</div>
          </div>
          <div class="text-center">
            <div class="text-2xl font-bold text-success">{@stats.consensus_count}</div>
            <div class="text-xs text-base-content/50 mt-0.5">Consensus</div>
          </div>
          <%= if @stats.avg_duration do %>
            <div class="text-center">
              <div class="text-2xl font-bold text-base-content">{format_session_time(@stats.avg_duration)}</div>
              <div class="text-xs text-base-content/50 mt-0.5">Avg per item</div>
            </div>
          <% end %>
          <%= if @stats.session_seconds do %>
            <div class="text-center">
              <div class="text-2xl font-bold text-base-content">{format_session_time(@stats.session_seconds)}</div>
              <div class="text-xs text-base-content/50 mt-0.5">Session time</div>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  attr :lobby, :map, required: true
  attr :show_queue_form, :boolean, default: false
  attr :queue_form, :map, default: nil

  defp queue_progress_panel(assigns) do
    ~H"""
    <% total = length(@lobby.history) + (if @lobby.current_item, do: 1, else: 0) + length(@lobby.queue) %>
    <% completed = length(@lobby.history) %>
    <% current_position = completed + (if @lobby.current_item, do: 1, else: 0) %>
    <div class="mt-8 bg-base-200 rounded-xl p-5 border border-base-300">
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-semibold text-base-content/70 uppercase tracking-wider">Queue</h3>
        <%= if total > 0 do %>
          <span class="text-xs text-base-content/50">
            <%= if @lobby.current_item do %>
              Item {current_position} of {total}
            <% else %>
              {completed} of {total} done
            <% end %>
          </span>
        <% end %>
      </div>

      <%!-- Add item form for members (when members_can_add_to_queue is true) --%>
      <%= if @lobby.members_can_add_to_queue do %>
        <div class="mb-4">
          <%= if @show_queue_form do %>
            <div class="bg-base-100 rounded-xl p-4 mb-3 border border-base-300">
              <.form for={@queue_form} id="member-queue-form" phx-submit="add_to_queue">
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
                  <.button type="submit" class="btn btn-primary btn-sm">Add to queue</.button>
                  <.button
                    type="button"
                    phx-click="toggle_queue_form"
                    class="btn btn-ghost btn-sm"
                  >
                    Cancel
                  </.button>
                </div>
              </.form>
            </div>
          <% else %>
            <.button
              id="member-toggle-queue-form"
              phx-click="toggle_queue_form"
              class="btn btn-ghost btn-xs"
            >
              <.icon name="hero-plus-micro" class="size-3.5" /> Add item
            </.button>
          <% end %>
        </div>
      <% end %>

      <%!-- Progress bar --%>
      <%= if total > 0 do %>
        <% pct = Float.round(completed / total * 100, 1) %>
        <div class="w-full bg-base-300 rounded-full h-1.5 mb-4 overflow-hidden">
          <div
            class="bg-primary h-1.5 rounded-full transition-all duration-500"
            style={"width: #{pct}%;"}
          >
          </div>
        </div>
      <% end %>

      <%!-- History summary --%>
      <%= if completed > 0 do %>
        <p class="text-xs text-base-content/40 mb-3">
          {completed} item{if completed == 1, do: "", else: "s"} completed
        </p>
      <% end %>

      <%!-- Upcoming queue items (read-only) --%>
      <%= if @lobby.queue != [] do %>
        <div class="space-y-1.5">
          <p class="text-xs text-base-content/40 uppercase tracking-wider mb-2">Up next</p>
          <%= for {item, index} <- Enum.with_index(@lobby.queue) do %>
            <div class="flex items-center gap-3 bg-base-100 rounded-lg px-3 py-2 border border-base-300">
              <span class="text-xs text-base-content/30 font-mono tabular-nums w-5 shrink-0 text-right">
                {current_position + index + 1}.
              </span>
              <span class="flex-1 text-sm text-base-content/70 truncate">{item.title}</span>
              <%= if item.context_url do %>
                <a
                  href={item.context_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="shrink-0 text-base-content/30 hover:text-primary transition-colors"
                  title="View context"
                >
                  <.icon name="hero-arrow-top-right-on-square-micro" class="size-3.5" />
                </a>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <%= if @lobby.queue == [] && completed == 0 do %>
        <p class="text-sm text-base-content/40 text-center py-2">No items queued yet.</p>
      <% end %>
    </div>
    """
  end

  defp elapsed_seconds(nil), do: 0

  defp elapsed_seconds(opened_at) do
    DateTime.diff(DateTime.utc_now(), opened_at, :second)
  end

  defp format_elapsed(seconds) when seconds < 60, do: "Open for #{seconds}s"

  defp format_elapsed(seconds) when seconds < 3_600 do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    "Open for #{m}m #{s}s"
  end

  defp format_elapsed(seconds) do
    h = div(seconds, 3_600)
    m = div(rem(seconds, 3_600), 60)
    "Open for #{h}h #{m}m"
  end

  defp format_duration(nil), do: nil

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    if s == 0, do: "#{m}m", else: "#{m}m #{s}s"
  end

  defp build_csv(history) do
    header = "Item,Avg,Median,Min,Max,Consensus,Votes\r\n"

    rows =
      Enum.map(history, fn entry ->
        item_title = csv_escape(entry.item && entry.item.title || "")
        avg = entry.stats.avg || ""
        median = entry.stats.median || ""
        min = entry.stats.min || ""
        max = entry.stats.max || ""
        consensus = if entry.stats.consensus?, do: "Yes", else: "No"

        votes =
          entry.votes
          |> Map.values()
          |> Enum.join(" | ")
          |> csv_escape()

        "#{item_title},#{avg},#{median},#{min},#{max},#{consensus},#{votes}\r\n"
      end)

    IO.iodata_to_binary([header | rows])
  end

  defp csv_escape(value) do
    str = to_string(value)

    if String.contains?(str, [",", "\"", "\r", "\n"]) do
      "\"#{String.replace(str, "\"", "\"\"")}\""
    else
      str
    end
  end

  defp build_json(history) do
    data =
      Enum.map(history, fn entry ->
        %{
          item: %{
            id: entry.item && entry.item.id,
            title: entry.item && entry.item.title,
            context_url: entry.item && entry.item.context_url
          },
          stats: %{
            avg: entry.stats.avg,
            median: entry.stats.median,
            min: entry.stats.min,
            max: entry.stats.max,
            consensus: entry.stats.consensus?
          },
          votes: entry.votes
        }
      end)

    Jason.encode!(data, pretty: true)
  end

  defp build_markdown(history) do
    header = "# Planning Poker History\n\n| Item | Avg | Median | Min | Max | Consensus | Votes |\n|------|-----|--------|-----|-----|-----------|-------|\n"

    rows =
      Enum.map(history, fn entry ->
        title = (entry.item && entry.item.title || "") |> String.replace("|", "\\|")
        avg = entry.stats.avg || ""
        median = entry.stats.median || ""
        min = entry.stats.min || ""
        max = entry.stats.max || ""
        consensus = if entry.stats.consensus?, do: "Yes", else: "No"
        votes = entry.votes |> Map.values() |> Enum.join(", ")

        "| #{title} | #{avg} | #{median} | #{min} | #{max} | #{consensus} | #{votes} |\n"
      end)

    IO.iodata_to_binary([header | rows])
  end

  defp get_presence_meta(presence, user_id) do
    case Map.get(presence, user_id) do
      %{metas: [meta | _]} -> meta
      _ -> nil
    end
  end

  defp vote_tier("?", _cards_ordered, _median), do: :clarification

  defp vote_tier(card, cards_ordered, median) do
    median_card = snap_median_to_card(median, cards_ordered)

    case {median_card, Enum.find_index(cards_ordered, &(&1 == card)),
          Enum.find_index(cards_ordered, &(&1 == median_card))} do
      {nil, _, _} ->
        :middle

      {_, nil, _} ->
        :middle

      {_, card_idx, median_idx} ->
        distance = abs(card_idx - median_idx)

        cond do
          distance == 0 -> :near_consensus
          distance == 1 -> :middle
          true -> :outlier
        end
    end
  end

  defp format_session_time(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_session_time(seconds) when seconds < 3_600 do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    if s == 0, do: "#{m}m", else: "#{m}m #{s}s"
  end

  defp format_session_time(seconds) do
    h = div(seconds, 3_600)
    m = div(rem(seconds, 3_600), 60)
    if m == 0, do: "#{h}h", else: "#{h}h #{m}m"
  end

  defp session_stats(history, opened_at) do
    total_items = length(history)
    consensus_count = Enum.count(history, fn e -> e.stats.consensus? end)

    all_durations = Enum.flat_map(history, fn e ->
      case e[:duration_seconds] do
        nil -> []
        d -> [d]
      end
    end)

    avg_duration =
      if all_durations != [] do
        round(Enum.sum(all_durations) / length(all_durations))
      else
        nil
      end

    session_seconds =
      if opened_at do
        DateTime.diff(DateTime.utc_now(), opened_at, :second)
      else
        nil
      end

    %{
      total_items: total_items,
      consensus_count: consensus_count,
      avg_duration: avg_duration,
      session_seconds: session_seconds
    }
  end

  defp snap_median_to_card(nil, _cards), do: nil

  defp snap_median_to_card(median, cards) do
    numeric_cards =
      Enum.flat_map(cards, fn c ->
        case Float.parse(to_string(c)) do
          {n, ""} -> [{n, c}]
          _ -> []
        end
      end)

    case numeric_cards do
      [] ->
        nil

      _ ->
        {_val, card_str} = Enum.min_by(numeric_cards, fn {n, _c} -> abs(n - median) end)
        card_str
    end
  end

  defp nilify(""), do: nil
  defp nilify(val), do: val

  defp generate_id do
    :crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false)
  end
end
