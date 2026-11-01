defmodule App.ReportTest do
  use App.DataCase, async: true

  import App.DataFixtures
  import ExUnit.CaptureLog

  alias App.Model.Activity
  alias App.Model.Member
  alias App.Report
  alias App.Report.Catalog
  alias App.Report.Error
  alias App.Report.Plan
  alias App.Report.Runner

  @now ~U[2026-06-15 19:00:00Z]

  defp run!(text, team, given \\ %{}) do
    {:ok, result} = Report.run(text, team, given, @now)
    result
  end

  defp error(text, team),
    do: text |> Report.check(team, %{}, @now) |> then(fn {:error, e} -> Error.text(e) end)

  describe "the catalog" do
    test "every field has a label and a type, and every subject runs" do
      team = team_fixture()

      for subject <- Catalog.subjects() do
        assert subject.label != nil and subject.one != nil and subject.many != nil

        for field <- subject.fields do
          assert is_binary(field.label) and field.label != "",
                 "#{subject.name}.#{field.name} has no label"

          assert field.type in [:text, :number, :hours, :km, :date, :bool, :list, :choice] or
                   match?(
                     {:record, kind}
                     when kind in [:member, :activity, :item, :qualification, :group],
                     field.type
                   ),
                 "#{subject.name}.#{field.name} has no type"
        end

        names =
          subject.fields
          |> Enum.filter(&(&1.args == []))
          |> Enum.map_join(", ", & &1.name)

        assert {:ok, %{rows: []}} =
                 Report.run("select #{names} from #{subject.name}", team, %{}, @now)
      end
    end

    test "reports leave out contact details" do
      team = team_fixture()

      assert error("select email from members", team) ==
               "Line 1: Reports leave out contact details. members has no field email."

      assert error("select member.phone from attendance", team) =~
               "Reports leave out contact details."
    end
  end

  test "a report reads one team's records, whatever its where says" do
    team = team_fixture()
    other = team_fixture()
    member = member_fixture(team, %{name: "Avery Chen"})
    member_fixture(other, %{name: "Blake Morrison"})
    activity = activity_fixture(other, %{started_at: ~U[2026-06-01 18:00:00Z]})
    attendance_fixture(activity, member)

    assert run!("select name from members where counted = true or counted = false", team).rows ==
             [[member.id]]

    assert run!("select id from attendance", team).rows == []
    assert run!("select id from attendance", other).rows == []
  end

  # No group by: one row that counts every row, on the team's records only.
  test "count without group by counts every row" do
    team = team_fixture()
    member_fixture(team)
    member_fixture(team)
    member_fixture(team_fixture())

    assert run!("select count(id) from members", team).rows == [[2]]
    assert run!("select count(id) from members totals", team).totals == [2]
  end

  # Only an interrupted run took too long. Any other error is bad SQL, logged as a bug. The
  # slow run goes last: its timeout drops the test's connection.
  test "a run past the time limit says to narrow it; other errors say it could not run" do
    log =
      capture_log(fn ->
        assert {:error,
                %Error{message: "This report could not run. Try again, or change its query."}} =
                 Runner.run(%Plan{sql: "SELECT 1 GROUP BY", params: []}, "Etc/UTC")
      end)

    assert log =~ "Report could not run: incomplete input"

    slow =
      "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 1000000000) SELECT count(*) FROM c"

    capture_log(fn ->
      assert {:error, %Error{message: "Narrow the report with where" <> _}} =
               Runner.run(%Plan{sql: slow, params: []}, "Etc/UTC")
    end)
  end

  test "hours by member pivots by kind, with a total row and column" do
    team = team_fixture()
    avery = member_fixture(team, %{name: "Avery Chen"})
    blake = member_fixture(team, %{name: "Blake Morrison"})

    exercise =
      activity_fixture(team, %{activity_kind: "exercise", started_at: ~U[2026-03-01 18:00:00Z]})

    incident =
      activity_fixture(team, %{activity_kind: "incident", started_at: ~U[2026-04-01 18:00:00Z]})

    coming =
      activity_fixture(team, %{activity_kind: "incident", started_at: ~U[2026-07-01 18:00:00Z]})

    attendance_fixture(exercise, avery, %{duration_in_minutes: 120})
    attendance_fixture(incident, avery, %{duration_in_minutes: 90})
    attendance_fixture(exercise, blake, %{duration_in_minutes: 60})
    attendance_fixture(incident, blake, %{duration_in_minutes: 30, status: "absent"})
    attendance_fixture(coming, blake, %{duration_in_minutes: 600})

    result =
      run!(
        """
        select member, sum(hours) from attendance
        where status = 'Attended' and year(activity.started_at) = :year and member.counted = true
        group by member pivot activity.kind order by member.name totals
        """,
        team
      )

    assert Enum.map(result.columns, & &1.label) == ["Member", "Incident", "Exercise", "Total"]
    assert result.rows == [[avery.id, 90, 120, 210], [blake.id, nil, 60, 60]]
    assert result.totals == [nil, 90, 180, 270]
    assert [%{name: "year", kind: :year, value: 2026}] = result.values
  end

  # cspell:ignore Atended
  test "status says the glossary's words, and compares by them" do
    team = team_fixture()
    member = member_fixture(team)
    past = activity_fixture(team, %{started_at: ~U[2026-06-01 18:00:00Z]})
    coming = activity_fixture(team, %{started_at: ~U[2026-07-01 18:00:00Z]})
    attendance_fixture(past, member)
    attendance_fixture(coming, member)
    attendance_fixture(coming, member, %{status: "absent"})
    attendance_fixture(coming, member, %{status: "requested"})

    result =
      run!("select status, count(id) from attendance group by status order by status", team)

    assert result.rows == [
             ["attended", 1],
             ["cant_make_it", 1],
             ["no_reply", 1],
             ["signed_up", 1]
           ]

    assert hd(result.columns).choices |> Enum.map(&elem(&1, 0)) |> Enum.take(2) == [
             "Attended",
             "Signed up"
           ]

    assert run!("select id from attendance where status = 'can''t make it'", team).rows
           |> length() == 1

    assert error("select id from attendance where status = 'Atended'", team) ==
             "Line 1: status is never 'Atended'. Use one of: 'Attended', 'Signed up', 'Absent', 'Can't make it', 'No reply'."
  end

  test "dates are days in the team's time zone" do
    team = team_fixture(%{timezone: "America/Vancouver"})
    # 11:30 pm on December 31 in Vancouver.
    activity = activity_fixture(team, %{started_at: ~U[2026-01-01 07:30:00Z]})

    assert run!("select year(started_at), month(started_at) from activities", team).rows == [
             [2025, 12]
           ]

    assert run!("select id from activities where started_at = date '2025-12-31'", team).rows == [
             [activity.id]
           ]

    assert run!("select id from activities where year(started_at) = 2026", team).rows == []

    assert run!("select id from activities where started_at = LAST_YEAR", team).rows == [
             [activity.id]
           ]

    assert run!("select id from activities where started_at = THIS_YEAR", team).rows == []

    assert run!("select id from activities where started_at < LAST_N_DAYS:30", team).rows == [
             [activity.id]
           ]

    assert run!("select days_since(started_at) from activities", team).rows == [[166]]
  end

  # Toronto keeps daylight saving time, so one fixed offset would get one of these wrong.
  test "local dates follow daylight saving time" do
    team = team_fixture(%{timezone: "America/Toronto"})
    # 11:30 pm on June 30 (EDT) and on December 31 (EST).
    activity_fixture(team, %{started_at: ~U[2026-07-01 03:30:00Z]})
    activity_fixture(team, %{started_at: ~U[2026-01-01 04:30:00Z]})

    assert run!(
             "select year(started_at), month(started_at) from activities order by started_at",
             team
           ).rows ==
             [[2025, 12], [2026, 6]]
  end

  test "a value takes its default, or the one given" do
    team = team_fixture()
    activity_fixture(team, %{started_at: ~U[2025-05-01 18:00:00Z]})
    this_year = activity_fixture(team, %{started_at: ~U[2026-05-01 18:00:00Z]})
    query = "select id from activities where year(started_at) = :year"

    result = run!(query, team)
    assert result.rows == [[this_year.id]]

    assert [%{kind: :year, value: 2026, choices: [{"2026", "2026"}, {"2025", "2025"}]}] =
             result.values

    assert run!(query, team, %{"year" => "2025"}).rows |> length() == 1

    group = group_fixture(team, %{title: "Callout"})
    member = member_fixture(team)
    group_member_fixture(group, member)
    result = run!("select name from members where groups includes (:group)", team)
    assert result.rows == [[member.id]]
    assert [%{kind: :choice, value: "Callout"}] = result.values
  end

  test "not_seen counts from the attendance clock, as Needs attention does" do
    team = team_fixture()
    seen = member_fixture(team, %{joined_at: ~U[2020-01-01 00:00:00Z]})
    not_seen = member_fixture(team, %{joined_at: ~U[2020-01-01 00:00:00Z]})
    new = member_fixture(team, %{joined_at: ~U[2026-05-01 00:00:00Z]})
    attendance_fixture(activity_fixture(team, %{started_at: ~U[2026-01-01 18:00:00Z]}), seen)
    attendance_fixture(activity_fixture(team, %{started_at: ~U[2024-01-01 18:00:00Z]}), not_seen)

    expected =
      Member |> Member.not_seen_query(team, 365, @now) |> select([m], [m.id]) |> Repo.all()

    assert run!("select name from members where not_seen(365)", team).rows == expected
    assert expected == [[not_seen.id]]
    refute [new.id] in expected
  end

  test "hours_tag_count is the count the hours tag checks use" do
    team = team_fixture()
    none = activity_fixture(team, %{tags: ["Rope"]})
    one = activity_fixture(team, %{tags: ["Primary Hours"]})
    two = activity_fixture(team, %{tags: ["Primary Hours", "Secondary Hours"]})
    hours_tags = Activity.hours_tags(team)

    ids = fn query ->
      query |> where([a], a.team_id == ^team.id) |> select([a], [a.id]) |> Repo.all()
    end

    untagged = Activity.without_hours_tag(Activity, hours_tags)
    doubled = Activity.with_two_hours_tags(Activity, hours_tags)

    assert run!("select id from activities where hours_tag_count = 0", team).rows ==
             ids.(untagged)

    assert run!("select id from activities where hours_tag_count > 1", team).rows == ids.(doubled)

    assert run!("select id, hours_tag_count from activities order by hours_tag_count", team).rows ==
             [[none.id, 0], [one.id, 1], [two.id, 2]]
  end

  test "standing and counted are the members list's" do
    team = team_fixture()
    retiring = group_fixture(team)

    team =
      team
      |> Ecto.Changeset.change(retiring_d4h_group_id: retiring.d4h_group_id)
      |> Repo.update!()

    active = member_fixture(team)
    leaving = member_fixture(team)
    bot = member_fixture(team, %{not_a_person: true})
    group_member_fixture(retiring, leaving)

    result = run!("select name, standing, counted from members order by id", team)

    assert result.rows == [
             [active.id, "active", true],
             [leaving.id, "retiring", false],
             [bot.id, "not_a_person", false]
           ]
  end

  test "a list includes or excludes titles, ignoring case" do
    team = team_fixture()
    first_aid = qualification_fixture(team, %{title: "First Aid"})
    holder = member_fixture(team)
    other = member_fixture(team)
    qualification_award_fixture(first_aid, holder, %{starts_at: ~U[2026-01-01 00:00:00Z]})

    assert run!("select name from members where qualifications includes ('first aid')", team).rows ==
             [[holder.id]]

    assert run!("select name from members where qualifications excludes ('First Aid')", team).rows ==
             [[other.id]]
  end

  test "each mistake names its line and how to fix it" do
    team = team_fixture()

    for {text, message} <- [
          {"select title, hour_tags from activities",
           "Line 1: activities has no field hour_tags. Did you mean hours_tag_count?"},
          {"select name from member",
           "Line 1: There is no subject member. Did you mean members?"},
          {"select member, count(id)\nfrom attendance",
           "Line 1: Add member to group by, or count it: count(member)."},
          {"select member, sum(hours) from attendance\ngroup by member\norder by started_at",
           "Line 3: Order by a field in group by, or a count, not started_at."},
          {"select name from members\nwhere count(id) > 3",
           "Line 2: Take count, sum, avg, min, and max out of where: it picks rows before they are counted."},
          {"select kind from activities pivot kind",
           "Line 1: Add a count or sum to select for the pivot to show, such as count(id)."},
          {"select name from members where position includes ('Lead')",
           "Line 1: Use includes with a list field, such as groups or tags. For position, write in (...)."},
          {"select published = true from activities",
           "Line 1: Show a field, not a condition: move published = true into where."},
          {"select activity.member.name from attendance",
           "Line 1: Write one dot at most, such as member.name: activity.member.name has more."},
          {"select title from activities where attended_count > 'three'",
           "Line 1: Compare attended_count with a number, not text."},
          {"select title from activities limit 6000", "Write a limit of 5,000 or fewer."},
          {"select sum(title) from activities",
           "Line 1: sum adds up numbers and hours. title is an activity."},
          {"select title from activities where started_at = :from and title = LAST_YEAR",
           "Line 1: Compare LAST_YEAR with a date field, such as started_at = LAST_YEAR."}
        ] do
      assert error(text, team) == message, text
    end
  end
end
