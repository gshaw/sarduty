defmodule App.Model.TagTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Tag

  test "counts the team's tags on activities since a date, by title" do
    team = team_fixture()
    activity_fixture(team, %{tags: ["Boat", "Primary Hours"]})
    activity_fixture(team, %{tags: ["Boat"]})

    activity_fixture(team, %{
      tags: ["Boat"],
      started_at: ~U[2020-01-01 10:00:00Z],
      finished_at: ~U[2020-01-01 12:00:00Z]
    })

    activity_fixture(team_fixture(), %{tags: ["Boat"]})

    assert Tag.use_counts(team.id, ~U[2025-01-01 00:00:00Z]) ==
             %{"Boat" => 2, "Primary Hours" => 1}
  end
end
