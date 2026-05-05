defmodule PlanningPokerWeb.SessionController do
  use PlanningPokerWeb, :controller

  alias PlanningPoker.LobbyServer

  @valid_systems ~w(fibonacci tshirt powers_of_two days)

  def create(conn, %{"action_type" => "create"} = params) do
    user_id = params["user_id"] || generate_id()
    user_name = String.trim(params["user_name"] || "")
    user_avatar = params["user_avatar"] || "🐶"
    lobby_name = String.trim(params["lobby_name"] || "Untitled Lobby")
    planning_system = to_planning_system(params["planning_system"])

    user_attrs = %{name: user_name, avatar: user_avatar, role: :voter}

    lobby_attrs = %{
      name: lobby_name,
      creator_id: user_id,
      planning_system: planning_system,
      participants: %{user_id => user_attrs}
    }

    case LobbyServer.create(lobby_attrs) do
      {:ok, lobby_id} ->
        conn
        |> put_session("user_id", user_id)
        |> put_session("user_name", user_name)
        |> put_session("user_avatar", user_avatar)
        |> redirect(to: ~p"/lobby/#{lobby_id}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to create lobby: #{inspect(reason)}")
        |> redirect(to: ~p"/")
    end
  end

  def create(conn, %{"action_type" => "join"} = params) do
    user_id = params["user_id"] || generate_id()
    user_name = String.trim(params["user_name"] || "")
    user_avatar = params["user_avatar"] || "🐶"
    lobby_id = params["lobby_id"] || ""

    conn
    |> put_session("user_id", user_id)
    |> put_session("user_name", user_name)
    |> put_session("user_avatar", user_avatar)
    |> redirect(to: ~p"/lobby/#{lobby_id}")
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Invalid request")
    |> redirect(to: ~p"/")
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  defp to_planning_system(s) when s in @valid_systems, do: String.to_atom(s)
  defp to_planning_system(_), do: :fibonacci

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
