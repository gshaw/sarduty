defmodule App.CoastRangeTest do
  use ExUnit.Case, async: true

  alias App.CoastRange
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Model.Member
  alias App.Operation.BuildMileageReport

  # cspell:ignore Kowal Noor Priya

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

  describe "who to use (App.CoastRange's moduledoc)" do
    setup do
      rows = CoastRange.build(@now)
      today = Service.Period.today(@now, CoastRange.timezone())
      members = for {:member, name, row, _} <- rows, into: %{}, do: {name, row}
      titles = for {:qualification, id, q, _} <- rows, into: %{}, do: {id, q.title}

      # Each member's awards, by title, as days from today to expiry.
      awards =
        for {:award, {q, name}, award, _} <- rows, award.ends_at, reduce: %{} do
          acc ->
            days = award.ends_at |> DateTime.to_date() |> Date.diff(today)
            Map.update(acc, name, %{titles[q] => days}, &Map.put(&1, titles[q], days))
        end

      held =
        for {:equipment_item, _, item, member_id: {:member, name}} <- rows, do: {name, item.title}

      groups = for {:group_member, {_group, name}, _, _} <- rows, do: name

      chores =
        for {:chore, _, chore, links} <- rows,
            do: {elem(links[:member_id], 1), chore.status}

      %{
        rows: rows,
        today: today,
        members: members,
        awards: awards,
        held: held,
        groups: groups,
        chores: chores
      }
    end

    test "the team admin, the member, and the leaders", c do
      assert c.members["Alex Chen"].d4h_permission == 0
      assert [0] == for({_, m} <- c.members, m.d4h_permission == 0, do: m.d4h_permission)
      assert c.awards["Cameron Ruiz"]["First aid"] == 15
      assert {"Cameron Ruiz", "Radio 3"} in c.held
      assert {"Cameron Ruiz", :waiting} in c.chores
      assert c.awards["Avery Chen"]["First aid"] == 25
      assert {"Blake Morrison", "Rope kit B"} in c.held
      assert c.awards["Blake Morrison"]["Rope rescue technician"] == 20

      leaders = for {:group_member, {9_500_004, name}, _, _} <- c.rows, do: name
      assert leaders == ["Alex Chen", "Avery Chen", "Harper Nguyen"]
    end

    test "Casey has nothing to flag", c do
      casey = c.members["Casey Dhillon"]

      assert casey.address && casey.d4h_permission == 3 && casey.d4h_status == "OPERATIONAL"
      assert c.awards["Casey Dhillon"] |> Map.values() |> Enum.all?(&(&1 > 90))
      refute Enum.any?(c.held, &(elem(&1, 0) == "Casey Dhillon"))
    end

    test "each case is its one member", c do
      assert [%{starts_on: starts, ends_on: ends}] = rows(:away_period)
      assert {Date.diff(starts, c.today), Date.diff(ends, c.today)} == {-10, 20}

      assert c.awards["Drew Patel"]["First aid"] == -10
      assert c.awards["Priya Nair"]["Swiftwater rescue technician"] < 0

      assert [eli] =
               for(
                 m <- Map.values(c.members),
                 m.address == nil and not m.not_a_person,
                 do: m.name
               )

      assert eli == "Eli Haddad"

      assert [{_, %{name: "Quinn Laval"}}] =
               Enum.filter(c.members, fn {_, m} -> m.d4h_permission == 4 end)

      assert {"Jordan Lee", :waiting} in c.chores
      assert {"Noor Aziz", :accepted} in c.chores and {"Priya Nair", :accepted} in c.chores
      assert {"Sam Rivera", "Radio 2"} in c.held
    end

    test "Riley is new: in no group, with no award", c do
      assert DateTime.diff(@now, c.members["Riley Okafor"].joined_at, :day) == 40
      refute "Riley Okafor" in c.groups
      refute Enum.any?(c.rows, &match?({:award, {_, "Riley Okafor"}, _, _}, &1))
    end

    test "the activities by title", c do
      activities = for {:activity, _, a, _} <- c.rows, do: a
      by_title = &Enum.find(activities, fn a -> a.title == &1 end)

      newest =
        activities
        |> Enum.filter(&(&1.activity_kind == "incident"))
        |> Enum.max_by(& &1.started_at, DateTime)

      assert newest.title == "Missing hiker" and not newest.is_published
      refute Map.has_key?(newest.custom_values, "9400002")
      assert by_title.("Evidence search").tags == []
      assert "Secondary Hours" in by_title.("Missing hunter").tags
      assert days_away(by_title.("Trail safety booth"), c.today) == 4
      assert days_away(by_title.("Night search exercise"), c.today) == 12

      # The coming Tuesday's training has each reply.
      week = DateTime.add(@now, 7, :day)

      [tuesday] =
        for a <- activities,
            a.activity_kind == "exercise",
            DateTime.after?(a.started_at, @now) and DateTime.before?(a.started_at, week),
            do: a

      statuses =
        for {:attendance, {id, _}, row, _} <- c.rows,
            id == tuesday.d4h_activity_id,
            uniq: true,
            do: row.status

      assert Enum.sort(statuses) == ["absent", "attending", "requested"]
    end
  end

  describe "what a demo shows off" do
    setup do
      visitor = %{name: "Morgan Visitor", email: "morgan@example.com"}
      %{rows: CoastRange.build(@now, visitor: visitor)}
    end

    test "only a demo has a visitor" do
      refute @now
             |> CoastRange.build()
             |> Enum.any?(fn {_kind, key, _row, links} ->
               key == :visitor or {:member, :visitor} in Keyword.values(links)
             end)
    end

    test "the visitor has things to do the moment they open the Dashboard", c do
      today = Service.Period.today(@now, CoastRange.timezone())
      activities = for {:activity, id, a, _} <- c.rows, into: %{}, do: {id, a}

      mine = for {:attendance, {id, :visitor}, row, _} <- c.rows, do: {activities[id], row}

      assert Enum.any?(mine, fn {a, row} ->
               a.title == "Missing hiker" and row.status == "attending"
             end)

      for {a, row} <- mine,
          not Activity.started?(a, @now),
          do: assert(row.status == "requested", a.title)

      [first_aid] = for {:award, {9_600_002, :visitor}, award, _} <- c.rows, do: award
      assert first_aid.ends_at |> DateTime.to_date() |> Date.diff(today) == 30

      assert [%{code: nil}] = for({:member_card, :visitor, card, _} <- c.rows, do: card)

      assert [%{travel: "icp", checked_at: nil}] =
               for(
                 {:trip, _, trip, links} <- c.rows,
                 links[:member_id] == {:member, :visitor},
                 activities[elem(links[:activity_id], 1)].title == "Missing hiker",
                 do: trip
               )
    end

    test "travel: Missing hiker part way, Overdue kayakers ready to publish", c do
      activities = for {:activity, id, a, _} <- c.rows, into: %{}, do: {id, a}

      by_title =
        Enum.group_by(
          for(
            {:trip, _, trip, links} <- c.rows,
            do: {activities[elem(links[:activity_id], 1)], trip}
          ),
          &elem(&1, 0).title,
          &elem(&1, 1)
        )

      assert Enum.all?(by_title["Overdue kayakers"], & &1.checked_at)
      assert Enum.any?(by_title["Missing hiker"], &(&1.checked_at == nil))

      attended =
        for {:attendance, {id, _}, row, _} <- c.rows,
            activities[id].title == "Missing hiker",
            row.status == "attending",
            do: row

      assert length(by_title["Missing hiker"]) < length(attended), "a row isn't set"
    end

    # Saved homes and routes mean the Travel tab never asks Mapbox, and the km a team
    # admin set are the km the report works out.
    test "each trip's km is the mileage report's", c do
      activities = for {:activity, id, a, _} <- c.rows, into: %{}, do: {id, a}

      homes =
        for {:home_coordinate, key, home, _} <- c.rows, into: %{}, do: {key, home.coordinate}

      distances =
        for {:route_distance, pair, route, _} <- c.rows, into: %{}, do: {pair, route.metres}

      point = &(&1 |> Coordinate.build() |> Coordinate.to_string(5))
      yard = point.("49.2,-123.1")

      for {:trip, _, trip, links} <- c.rows, trip.travel in ["icp", "yard"] do
        {:member, key} = links[:member_id]
        activity = activities[elem(links[:activity_id], 1)]
        row = %{member_id: key, member: %{name: key}}

        [report] =
          BuildMileageReport.build([row], homes, distances, point.(activity.coordinate), yard).rows

        km = if trip.travel == "icp", do: report.activity_km, else: report.yard_km
        assert trip.km == km, inspect(key)
      end
    end

    test "each home's address is its member's, so the report never looks it up again", c do
      members = for {:member, key, m, _} <- c.rows, into: %{}, do: {key, m}

      for {:home_coordinate, key, home, _} <- c.rows,
          do: assert(home.address == members[key].address)
    end

    test "group rules with changes to review, templates, notes, and places", c do
      kinds = c.rows |> Enum.map(&elem(&1, 0)) |> Enum.frequencies()

      assert kinds[:group_rule] == 4
      assert kinds[:template] == 3
      assert kinds[:whiteboard_note] == 3
      assert kinds[:location_bookmark] == 3

      # Callout's rule takes off Dana, away; Swiftwater team's takes off Priya, expired.
      assert {9_500_001, "Dana Kowal"} in for({:group_member, key, _, _} <- c.rows, do: key)
      assert {9_500_003, "Priya Nair"} in for({:group_member, key, _, _} <- c.rows, do: key)
    end
  end

  defp days_away(activity, today) do
    activity.started_at
    |> DateTime.shift_zone!(CoastRange.timezone())
    |> DateTime.to_date()
    |> Date.diff(today)
  end
end
