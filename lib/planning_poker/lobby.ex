defmodule PlanningPoker.Lobby do
  @avatars ~w(🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐸 🐵 🐙 🦋 🦄)

  @planning_systems [
    {:fibonacci, "Fibonacci (1,2,3,5,8…)"},
    {:hours, "Man Hours (1h,2h,4h,8h…)"},
    {:tshirt, "T-Shirt Sizes (XS–XXL)"},
    {:powers_of_two, "Powers of Two (1,2,4,8…)"},
    {:days, "Days (1,2,3,4,5,7…)"},
    {:custom, "Custom…"}
  ]

  def avatars, do: @avatars
  def planning_systems, do: @planning_systems

  defstruct [
    :id,
    :name,
    :creator_id,
    opened_at: nil,
    planning_system: :fibonacci,
    custom_cards: [],
    auto_reveal: false,
    members_can_add_to_queue: false,
    state: :waiting,
    current_item: nil,
    voting_started_at: nil,
    votes: %{},
    vote_notes: %{},
    queue: [],
    history: [],
    participants: %{},
    pending_host_transfer: nil,
    buzz_cooldown_until: nil
  ]

  @card_systems %{
    fibonacci: ["0", "1", "2", "3", "5", "8", "13", "21", "34", "55", "89", "?", "∞", "☕"],
    hours: ["1h", "2h", "4h", "8h", "12h", "16h", "24h", "32h", "?", "∞"],
    tshirt: ["0", "XS", "S", "M", "L", "XL", "XXL", "?", "∞"],
    powers_of_two: ["0", "1", "2", "4", "8", "16", "32", "64", "?", "∞"],
    days: ["0", "1", "2", "3", "4", "5", "7", "10", "14", "?", "∞"]
  }

  def cards(%__MODULE__{planning_system: :custom, custom_cards: cards}), do: cards
  def cards(%__MODULE__{planning_system: system}), do: Map.fetch!(@card_systems, system)
  def cards(system) when is_atom(system), do: Map.fetch!(@card_systems, system)

  def compute_stats(votes) do
    all_values = Map.values(votes)

    numeric_values =
      all_values
      |> Enum.flat_map(fn v ->
        case Float.parse(to_string(v)) do
          {n, ""} -> [n]
          {n, "h"} -> [n]
          _ -> []
        end
      end)

    distribution = Enum.frequencies(all_values)
    clarification_count = Enum.count(all_values, &(&1 == "?"))

    if Enum.empty?(numeric_values) do
      %{
        avg: nil,
        median: nil,
        min: nil,
        max: nil,
        consensus?: false,
        distribution: distribution,
        clarification_count: clarification_count
      }
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
        distribution: distribution,
        clarification_count: clarification_count
      }
    end
  end
end
