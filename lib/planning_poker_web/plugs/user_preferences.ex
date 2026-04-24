defmodule PlanningPokerWeb.Plugs.UserPreferences do
  import Plug.Conn

  @cookie "_pp_prefs"

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, "user_name") not in [nil, ""] do
      conn
    else
      conn = fetch_cookies(conn)

      case conn.cookies[@cookie] do
        nil ->
          conn

        raw ->
          case Jason.decode(raw) do
            {:ok, %{"user_name" => name, "user_avatar" => avatar}} when name != "" ->
              conn
              |> put_session("user_name", name)
              |> put_session("user_avatar", avatar)

            _ ->
              conn
          end
      end
    end
  end
end
