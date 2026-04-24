defmodule PlanningPoker.MetricsServer do
  @moduledoc """
  Periodically broadcasts global metrics to connected clients via PubSub.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    metrics = PlanningPoker.Metrics.get_global_metrics()
    Phoenix.PubSub.broadcast(PlanningPoker.PubSub, "metrics", {:metrics_updated, metrics})
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, 1000)
  end
end
