defmodule App.Report.ListsTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Team
  alias App.Report
  alias App.Report.Lists

  @now ~U[2026-06-15 19:00:00Z]

  defp page!(team, params) do
    {:ok, view} = Report.page(Lists.activities().query, team, params, @now)
    view
  end

  defp titles(team, params) do
    view = page!(team, params)
    by_id = Activity |> where([a], a.team_id == ^team.id) |> Repo.all() |> Map.new(&{&1.id, &1})
    Enum.map(view.result.rows, &by_id[hd(&1)].title)
  end

  defp tiles(view), do: Map.new(view.switch.tiles, &{&1.value, &1.count})

  test "every list's text checks" do
    team = team_fixture()

    for slug <- ["activities", "members"] do
      assert {:ok, _plan} = Report.check(Lists.get(slug).query, team, %{}, @now)
      assert {:ok, _view} = Report.page(Lists.get(slug).query, team, %{}, @now)

      assert {:ok, _view} =
               Report.page(Lists.get(slug).query, team, %{}, @now, team_admin?: false)
    end
  end

  describe "Activities' chore activities (#575)" do
    setup do
      team = member_logins_team_fixture()
      activity_fixture(team, %{title: "Board meeting", activity_kind: "event"})
      activity_fixture(team, %{title: "Rope rescue night", activity_kind: "exercise"})
      chore_activity_fixture(team, [90, 30])
      %{team: team}
    end

    test "are their own kind, in All but not Events", %{team: team} do
      assert team |> titles(%{}) |> Enum.sort() ==
               ["Board meeting", "Chores: Equipment maintenance", "Rope rescue night"]

      assert titles(team, %{"activity" => "event"}) == ["Board meeting"]
      assert titles(team, %{"activity" => "chores"}) == ["Chores: Equipment maintenance"]
    end

    test "count apart from D4H's kinds, and in All", %{team: team} do
      assert team |> page!(%{}) |> tiles() ==
               %{"all" => 3, "incident" => 0, "event" => 1, "exercise" => 1, "chores" => 1}
    end

    test "sort by their members' total", %{team: team} do
      chore_activity_fixture(team, [600], %{title: "Chores: Board work"})

      assert titles(team, %{"activity" => "chores", "sort" => "hours"}) ==
               ["Chores: Board work", "Chores: Equipment maintenance"]
    end

    test "only the team's own chore events count", %{team: team} do
      other = member_logins_team_fixture()
      chore_activity_fixture(other, [60])

      assert titles(team, %{"activity" => "chores"}) == ["Chores: Equipment maintenance"]
    end
  end

  test "Activities' Required fields: Missing keeps those with a required field left empty (#681)" do
    team = team_fixture()
    custom_field_fixture(team, %{d4h_custom_field_id: 454, required: true})

    activity_fixture(team, %{title: "Missing file", activity_kind: "incident", custom_values: %{}})

    activity_fixture(team, %{
      title: "Filled",
      activity_kind: "incident",
      custom_values: %{"454" => "1"}
    })

    assert titles(team, %{"fields" => "missing"}) == ["Missing file"]
    assert team |> titles(%{}) |> Enum.sort() == ["Filled", "Missing file"]
    # A value that isn't an option is no pick.
    assert team |> titles(%{"fields" => "nope"}) |> Enum.sort() == ["Filled", "Missing file"]
  end

  test "a Records team has no Required fields filter: the field is not the team's to read" do
    team = team_fixture(%{d4h_api_host: D4H.records_host()})

    refute Enum.any?(page!(team, %{}).filters, &(&1.name == "fields"))
    assert Enum.any?(page!(team_fixture(), %{}).filters, &(&1.name == "fields"))
  end

  test "Activities' When options pick the sort that suits them" do
    team = team_fixture()

    for {when_, sort} <- [
          {"all", "date-"},
          {"current", "date"},
          {"recent", "date-"},
          {"past", "date-"},
          {"future", "date"}
        ] do
      assert page!(team, %{"when" => when_}).sort == sort, "when=#{when_}"
    end

    assert page!(team, %{"when" => "future", "sort" => "id-"}).sort == "id-"
  end

  describe "Members (#784)" do
    defp members_page(team, params, opts \\ []) do
      {:ok, view} = Report.page(Lists.members().query, team, params, @now, opts)
      view
    end

    test "Attended offers every time frame a team can watch, as Home's link names it" do
      team = team_fixture()
      [attended] = Enum.filter(members_page(team, %{}).filters, &(&1.name == "attended"))

      assert tl(Enum.map(attended.options, &elem(&1, 1))) ==
               Enum.map(Team.not_seen_days(), &Integer.to_string/1)
    end

    test "a member gets Period, Group, and Tag, and the Active tile but not Away" do
      team = team_fixture()
      admin = members_page(team, %{})
      member = members_page(team, %{}, team_admin?: false)

      assert Enum.map(admin.filters, & &1.name) ==
               ~w(when group activity_tag details attended items access)

      assert Enum.map(member.filters, & &1.name) == ~w(when group activity_tag)

      assert Enum.map(member.switch.tiles, & &1.value) ==
               ~w(all current active retiring retired not_a_person)

      assert "away" in Enum.map(admin.switch.tiles, & &1.value)
    end

    test "Period starts on this year; the Activities and Hours columns follow Period and Tag" do
      team = team_fixture()
      tag_fixture(team, "Rope")
      avery = member_fixture(team, %{joined_at: ~U[2020-01-01 00:00:00Z]})

      rope =
        activity_fixture(team, %{
          tags: ["Rope"],
          started_at: ~U[2026-03-01 18:00:00Z],
          finished_at: ~U[2026-03-01 20:00:00Z]
        })

      other =
        activity_fixture(team, %{
          started_at: ~U[2026-04-01 18:00:00Z],
          finished_at: ~U[2026-04-01 19:00:00Z]
        })

      attendance_fixture(rope, avery, %{duration_in_minutes: 120})
      attendance_fixture(other, avery, %{duration_in_minutes: 60})

      view = members_page(team, %{})
      assert Enum.find(view.filters, &(&1.name == "when")).picked == "2026"
      assert [[_id, _, _, _, 2, 180, _, _]] = view.result.rows

      view = members_page(team, %{"activity_tag" => "Rope"})
      assert [[_id, _, _, _, 1, 120, _, _]] = view.result.rows
    end
  end
end
