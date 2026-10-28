defmodule App.Operation.RefreshTeamDetailsTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Operation.RefreshTeamDetails

  @team %Team{name: "Old name", lat: 49.1, lng: -122.6, timezone: "America/Vancouver"}

  test "takes D4H's name, place, and time zone" do
    d4h_team = %D4H.Team{
      name: "New name",
      coordinate: {49.2, -122.8},
      timezone: "America/Toronto"
    }

    assert RefreshTeamDetails.plan(@team, d4h_team) ==
             %{name: "New name", lat: 49.2, lng: -122.8, timezone: "America/Toronto"}
  end

  test "a team with no place in D4H keeps its own" do
    d4h_team = %D4H.Team{name: "New name", coordinate: nil, timezone: "America/Vancouver"}
    assert %{lat: 49.1, lng: -122.6} = RefreshTeamDetails.plan(@team, d4h_team)
  end
end
