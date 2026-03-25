defmodule PlanningPoker.Lobby do
  defstruct [
    :id,
    :name,
    :creator_id,
    opened_at: nil,
    planning_system: :fibonacci,
    auto_reveal: false,
    members_can_add_to_queue: false,
    state: :waiting,
    current_item: nil,
    voting_started_at: nil,
    votes: %{},
    queue: [],
    history: [],
    participants: %{},
    pending_host_transfer: nil
  ]

  @card_systems %{
    fibonacci: ["1", "2", "3", "5", "8", "13", "21", "34", "55", "89", "?", "∞", "☕"],
    tshirt: ["XS", "S", "M", "L", "XL", "XXL", "?", "∞"],
    powers_of_two: ["1", "2", "4", "8", "16", "32", "64", "?", "∞"],
    days: ["1", "2", "3", "4", "5", "7", "10", "14", "?", "∞"]
  }

  def cards(system), do: Map.fetch!(@card_systems, system)

  def compute_stats(votes) do
    numeric_values =
      votes
      |> Map.values()
      |> Enum.flat_map(fn v ->
        case Float.parse(to_string(v)) do
          {n, ""} -> [n]
          _ -> []
        end
      end)

    distribution = votes |> Map.values() |> Enum.frequencies()

    if Enum.empty?(numeric_values) do
      %{avg: nil, median: nil, min: nil, max: nil, consensus?: false, distribution: distribution}
    else
      sorted = Enum.sort(numeric_values)
      count = length(sorted)
      avg = Float.round(Enum.sum(sorted) / count, 1)

      median =
        if rem(count, 2) == 0 do
          mid = div(count, 2)
          Float.round((Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2, 1)
        else
          Enum.at(sorted, div(count, 2))
        end

      all_values = Map.values(votes)

      consensus? =
        length(all_values) > 0 and
          length(Enum.uniq(numeric_values)) == 1 and
          length(numeric_values) == length(all_values)

      %{
        avg: avg,
        median: median,
        min: Enum.min(sorted),
        max: Enum.max(sorted),
        consensus?: consensus?,
        distribution: distribution
      }
    end
  end
end
