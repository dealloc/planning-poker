defmodule PlanningPoker.LobbyTest do
  use ExUnit.Case, async: true

  alias PlanningPoker.Lobby

  describe "compute_stats/1 chaos?" do
    test "true when three or more voters all pick different cards" do
      stats = Lobby.compute_stats(%{"a" => "1", "b" => "3", "c" => "8"})
      assert stats.chaos?
    end

    test "false when only two voters disagree" do
      stats = Lobby.compute_stats(%{"a" => "1", "b" => "3"})
      refute stats.chaos?
    end

    test "false when there is consensus" do
      stats = Lobby.compute_stats(%{"a" => "5", "b" => "5", "c" => "5"})
      refute stats.chaos?
      assert stats.consensus?
    end

    test "false when two voters share a card" do
      stats = Lobby.compute_stats(%{"a" => "1", "b" => "1", "c" => "3"})
      refute stats.chaos?
    end

    test "works for non-numeric cards like t-shirt sizes" do
      stats = Lobby.compute_stats(%{"a" => "S", "b" => "M", "c" => "XL"})
      assert stats.chaos?
    end
  end
end
