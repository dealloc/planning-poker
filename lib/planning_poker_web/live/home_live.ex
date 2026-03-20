defmodule PlanningPokerWeb.HomeLive do
  use PlanningPokerWeb, :live_view

  @avatars ~w(🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐸 🐵 🐙 🦋 🦄)

  @planning_systems [
    {"Fibonacci (1,2,3,5,8…)", "fibonacci"},
    {"T-Shirt Sizes (XS–XXL)", "tshirt"},
    {"Powers of Two (1,2,4,8…)", "powers_of_two"},
    {"Days (1,2,3,4,5,7…)", "days"}
  ]

  @impl true
  def mount(params, session, socket) do
    user_id = session["user_id"] || generate_id()
    user_name = session["user_name"] || ""
    user_avatar = session["user_avatar"] || hd(@avatars)

    join_id = params["join"]

    {mode, form} =
      if join_id do
        {
          :join,
          to_form(%{
            "user_name" => user_name,
            "lobby_id" => join_id
          })
        }
      else
        {
          :create,
          to_form(%{
            "user_name" => user_name,
            "lobby_name" => "",
            "planning_system" => "fibonacci"
          })
        }
      end

    socket =
      socket
      |> assign(:mode, mode)
      |> assign(:join_lobby_id, join_id)
      |> assign(:user_id, user_id)
      |> assign(:selected_avatar, user_avatar)
      |> assign(:avatars, @avatars)
      |> assign(:planning_systems, @planning_systems)
      |> assign(:form, form)
      |> assign(:page_title, "Planning Poker")

    {:ok, socket}
  end

  @impl true
  def handle_event("select_avatar", %{"avatar" => avatar}, socket) do
    {:noreply, assign(socket, :selected_avatar, avatar)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-[80vh] flex flex-col items-center justify-center py-12">
        <%!-- Logo / Hero --%>
        <div class="text-center mb-10">
          <div class="text-6xl mb-4">🃏</div>
          <h1 class="text-4xl font-bold tracking-tight text-base-content">Planning Poker</h1>
          <p class="mt-2 text-base-content/60 text-lg">Estimate together, ship faster.</p>
        </div>

        <%!-- Card --%>
        <div class="w-full max-w-md bg-base-200 rounded-2xl shadow-xl p-8">
          <%= if @mode == :join do %>
            <div class="mb-6">
              <h2 class="text-xl font-semibold text-base-content">Join Lobby</h2>
              <p class="text-sm text-base-content/60 mt-1">
                You're joining lobby
                <span class="font-mono font-bold text-primary">{@join_lobby_id}</span>
              </p>
            </div>

            <.form for={@form} id="join-form" action={~p"/session"} method="post">
              <input type="hidden" name="action_type" value="join" />
              <input type="hidden" name="user_id" value={@user_id} />
              <input type="hidden" name="user_avatar" value={@selected_avatar} />
              <input type="hidden" name="lobby_id" value={@join_lobby_id} />

              <.input
                field={@form[:user_name]}
                type="text"
                label="Your name"
                placeholder="What should we call you?"
                required
                autocomplete="off"
              />

              <div class="mb-4">
                <label class="label text-sm font-medium mb-2 block">Pick your avatar</label>
                <div class="grid grid-cols-8 gap-1.5">
                  <%= for avatar <- @avatars do %>
                    <button
                      type="button"
                      phx-click="select_avatar"
                      phx-value-avatar={avatar}
                      class={[
                        "text-2xl w-10 h-10 rounded-lg flex items-center justify-center transition-all duration-150",
                        "hover:bg-base-300 hover:scale-110 cursor-pointer",
                        if(@selected_avatar == avatar,
                          do: "bg-primary/20 ring-2 ring-primary scale-110",
                          else: "bg-base-100"
                        )
                      ]}
                    >
                      {avatar}
                    </button>
                  <% end %>
                </div>
              </div>

              <button
                type="submit"
                class="btn btn-primary w-full mt-2"
              >
                Join Lobby →
              </button>
            </.form>

            <div class="divider my-4 text-base-content/40">or</div>

            <.link navigate={~p"/"} class="btn btn-ghost w-full">
              Create a new lobby
            </.link>
          <% else %>
            <div class="mb-6">
              <h2 class="text-xl font-semibold text-base-content">Create a Lobby</h2>
              <p class="text-sm text-base-content/60 mt-1">Get your team ready to estimate.</p>
            </div>

            <.form for={@form} id="create-form" action={~p"/session"} method="post">
              <input type="hidden" name="action_type" value="create" />
              <input type="hidden" name="user_id" value={@user_id} />
              <input type="hidden" name="user_avatar" value={@selected_avatar} />

              <.input
                field={@form[:user_name]}
                type="text"
                label="Your name"
                placeholder="What should we call you?"
                required
                autocomplete="off"
              />

              <div class="mb-4">
                <label class="label text-sm font-medium mb-2 block">Pick your avatar</label>
                <div class="grid grid-cols-8 gap-1.5">
                  <%= for avatar <- @avatars do %>
                    <button
                      type="button"
                      phx-click="select_avatar"
                      phx-value-avatar={avatar}
                      class={[
                        "text-2xl w-10 h-10 rounded-lg flex items-center justify-center transition-all duration-150",
                        "hover:bg-base-300 hover:scale-110 cursor-pointer",
                        if(@selected_avatar == avatar,
                          do: "bg-primary/20 ring-2 ring-primary scale-110",
                          else: "bg-base-100"
                        )
                      ]}
                    >
                      {avatar}
                    </button>
                  <% end %>
                </div>
              </div>

              <.input
                field={@form[:lobby_name]}
                type="text"
                label="Lobby name"
                placeholder="Sprint 42 Planning…"
                required
                autocomplete="off"
              />

              <.input
                field={@form[:planning_system]}
                type="select"
                label="Card system"
                options={@planning_systems}
              />

              <button type="submit" class="btn btn-primary w-full mt-2">
                Create Lobby →
              </button>
            </.form>
          <% end %>
        </div>

        <p class="mt-6 text-sm text-base-content/40">
          Share the lobby link with your team to get started.
        </p>
      </div>
    </Layouts.app>
    """
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
