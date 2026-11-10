defmodule App.SilverBasinTest do
  use ExUnit.Case, async: true

  alias App.CoastRange
  alias App.SilverBasin

  @now ~U[2026-11-02 19:00:00Z]

  defp rows(kind), do: for({^kind, _key, row, _links} <- SilverBasin.build(@now), do: row)

  test "the same now builds the same rows" do
    assert SilverBasin.build(@now) == SilverBasin.build(@now)
  end

  # Issues and PRs are public, and the cast is in every demo.
  test "five members on 250-555-01xx, emails in plain letters, Jamie Sato the Owner" do
    members = rows(:member)

    assert Enum.map(members, & &1.name) == SilverBasin.names()
    assert Enum.map(members, & &1.phone) == for(n <- 1..5, do: "250-555-010#{n}")
    assert Enum.all?(members, &(&1.email =~ ~r/^[a-z.-]+@example\.com$/))
    assert [%{name: "Jamie Sato"}] = Enum.filter(members, &(&1.d4h_permission == 0))
  end

  test "no first or last name repeats one on Coast Range" do
    words = fn names -> names |> Enum.flat_map(&String.split/1) |> MapSet.new() end
    assert SilverBasin.names() |> words.() |> MapSet.disjoint?(words.(CoastRange.names()))
  end

  test "every member attended a training with hours, and every activity has hours" do
    activities = rows(:activity)
    assert Enum.count(activities, &(&1.activity_kind == "incident")) == 4
    assert Enum.count(activities, &(&1.activity_kind == "exercise")) == 2
    assert Enum.all?(activities, &("Primary Hours" in &1.tags and &1.is_published))

    trainings = for a <- activities, a.activity_kind == "exercise", do: a.d4h_activity_id

    attended =
      for {:attendance, {activity_id, name}, %{status: "attending"}, _links} <-
            SilverBasin.build(@now),
          activity_id in trainings,
          do: name

    for name <- SilverBasin.names(), do: assert(Enum.count(attended, &(&1 == name)) == 2)
  end

  test "names a cast's emails in plain letters" do
    assert CoastRange.email("Zoë Lefèvre") == "zoe.lefevre@example.com"
    assert CoastRange.email("Łukasz Wójcik") == "lukasz.wojcik@example.com"
    assert CoastRange.email("Trần Minh Châu") == "tran.minh.chau@example.com"
    assert CoastRange.email("Siobhán O'Connor-Hale") == "siobhan.oconnor-hale@example.com"
  end
end
