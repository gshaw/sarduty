defmodule App.CoastRangeTest do
  use ExUnit.Case, async: true

  alias App.CoastRange
  alias App.Model.Member

  # cspell:ignore Kowal

  @now ~U[2026-11-02 19:00:00Z]

  defp rows(kind, now \\ @now),
    do: for({^kind, _key, row, _links} <- CoastRange.build(now), do: row)

  test "the same now builds the same rows" do
    assert CoastRange.build(@now) == CoastRange.build(@now)
  end

  # Issues and PRs are public, and the cast is in every mockup.
  test "names, ref ids, and phone numbers never change, and none is real" do
    people = &Enum.map(&1, fn m -> {m.name, m.ref_id, m.phone} end)
    members = rows(:member)

    assert people.(members) == :member |> rows(DateTime.add(@now, 365, :day)) |> people.()
    assert Enum.all?(members, &(&1.phone =~ ~r/^604-555-01\d\d$/))
    assert Enum.all?(members, &(&1.email == nil or &1.email =~ ~r/@example\.com$/))
    assert hd(members).name == "Alex Chen"
    assert Enum.find(members, &(&1.ref_id == "132")).name == "Cameron Ruiz"
  end

  test "dates count back from now: a year of activities, and the coming week" do
    activities = rows(:activity)
    year_ago = DateTime.add(@now, -366, :day)
    week = DateTime.add(@now, 7, :day)
    coming? = &(DateTime.after?(&1, @now) and DateTime.before?(&1, week))

    assert Enum.all?(activities, &DateTime.after?(&1.started_at, year_ago))
    assert Enum.any?(activities, &coming?.(&1.started_at))

    assert :attendance
           |> rows()
           |> Enum.any?(&(&1.status == "attending" and coming?.(&1.started_at)))

    kinds = activities |> Enum.map(& &1.activity_kind) |> Enum.uniq() |> Enum.sort()
    assert kinds == ["event", "exercise", "incident"]
  end

  test "activities count up from 01400 in the order they started" do
    ref_ids =
      :activity |> rows() |> Enum.sort_by(& &1.started_at, DateTime) |> Enum.map(& &1.ref_id)

    assert hd(ref_ids) == "01400"
    assert ref_ids == Enum.sort(ref_ids)
  end

  test "every link names a row built before it" do
    @now
    |> CoastRange.build()
    |> Enum.reduce(MapSet.new(), fn {kind, key, _row, links}, built ->
      for {_field, ref} <- links,
          do: assert(MapSet.member?(built, ref), inspect({kind, key, ref}))

      MapSet.put(built, {kind, key})
    end)
  end

  test "an away member, a retiring one, a retired one, and one that isn't a person" do
    members = rows(:member)

    assert [%Member{name: "Robin Tse"}] = Enum.filter(members, &(&1.d4h_status == "RETIRED"))
    assert [%Member{name: "Duty pager"}] = Enum.filter(members, & &1.not_a_person)
    assert [%{reason: "Travelling"}] = rows(:away_period)
    assert :group |> rows() |> Enum.any?(&(&1.title == "Retiring"))
  end

  test "nobody has a row on an activity from before they joined" do
    joined = :member |> rows() |> Map.new(&{&1.name, &1.joined_at})

    for {:attendance, {_activity, name}, row, _links} <- CoastRange.build(@now) do
      assert DateTime.after?(row.started_at, joined[name]), name
    end
  end
end
