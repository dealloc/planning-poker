defmodule PlanningPoker.MCP.Server do
  use Anubis.Server,
    name: "Planning Poker MCP",
    version: "1.0.0",
    capabilities: [:tools]

  component(PlanningPoker.MCP.Tools.CreateLobby)
  component(PlanningPoker.MCP.Tools.GetLobby)
  component(PlanningPoker.MCP.Tools.GetLobbyItem)
  component(PlanningPoker.MCP.Tools.CreateLobbyItem)
  component(PlanningPoker.MCP.Tools.UpdateLobbyItem)

  @impl true
  def init(_client_info, frame), do: {:ok, frame}
end
