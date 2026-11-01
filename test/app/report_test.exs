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

    # A source selects only the columns a report reads, with only their joins (#784), so a
    # column whose join is missing from its `needs` fails here, alone, and not beside others.
    test "every field runs alone" do
      team = team_fixture()

      for subject <- Catalog.subjects(), field <- subject.fields, field.args == [] do
        assert {:ok, %{rows: []}} =
                 Report.run("select #{field.name} from #{subject.name}", team, %{}, @now),
               "#{subject.name}.#{field.name} does not run alone"
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

  describe "fields that are a rule's own query (#784)" do
    defp ids(text, team, given \\ %{}),
      do: text |> run!(team, given) |> Map.fetch!(:rows) |> Enum.map(&hd/1) |> Enum.sort()

    test "Activities' Current, Last 30 days, Missing fields, and chores" do
      team = team_fixture()
      now = @now
      two_days_ago = DateTime.add(now, -2, :day)

      current =
        activity_fixture(team, %{
          started_at: two_days_ago,
          finished_at: DateTime.add(two_days_ago, 3600)
        })

      recent =
        activity_fixture(team, %{
          started_at: DateTime.add(now, -20, :day),
          finished_at: DateTime.add(now, -20, :day)
        })

      _old =
        activity_fixture(team, %{
          started_at: DateTime.add(now, -90, :day),
          finished_at: DateTime.add(now, -90, :day)
        })

      chore =
        chore_activity_fixture(team, [30, 45], %{
          started_at: DateTime.add(now, -100, :day),
          finished_at: DateTime.add(now, -100, :day)
        })

      custom_field_fixture(team, %{required: true})
      long_ago = DateTime.add(now, -200, :day)

      missing =
        activity_fixture(team, %{
          activity_kind: "incident",
          custom_values: %{},
          started_at: long_ago,
          finished_at: long_ago
        })

      assert ids("select id from activities where current = true", team) == [current.id]

      assert ids("select id from activities where recent = true", team) ==
               Enum.sort([current.id, recent.id])

      assert ids("select id from activities where missing_required_fields", team) == [missing.id]
      assert ids("select id from activities where chore = true", team) == [chore.id]

      assert run!("select duration from activities where chore = true", team).rows == [[75]]
      assert run!("select duration from activities where id = #{current.id}", team).rows == [[60]]
    end

    test "Members' Period, totals by period and tag, and the members list's filters" do
      team = team_fixture()
      tag_fixture(team, "Rope")
      avery = member_fixture(team, %{name: "Avery Chen", joined_at: ~U[2020-01-01 00:00:00Z]})

      blake =
        member_fixture(team, %{
          name: "Blake Morrison",
          joined_at: ~U[2020-01-01 00:00:00Z],
          left_at: ~U[2025-06-01 00:00:00Z]
        })

      rope =
        activity_fixture(team, %{
          tags: ["Rope"],
          started_at: ~U[2026-03-01 18:00:00Z],
          finished_at: ~U[2026-03-01 20:00:00Z]
        })

      other =
        activity_fixture(team, %{
          tags: [],
          started_at: ~U[2026-04-01 18:00:00Z],
          finished_at: ~U[2026-04-01 19:00:00Z]
        })

      attendance_fixture(rope, avery, %{duration_in_minutes: 120})
      attendance_fixture(other, avery, %{duration_in_minutes: 60})

      assert ids("select id from members where on_team('2026')", team) == [avery.id]

      assert ids("select id from members where on_team('all')", team) ==
               Enum.sort([avery.id, blake.id])

      assert ids("select id from members where on_team(:when)", team, %{"when" => "2025"}) ==
               Enum.sort([avery.id, blake.id])

      assert ids("select id from members where current = true", team) == [avery.id]

      totals =
        "select name, activity_count(:when, :tag), attended_minutes(:when, :tag) from members where current"

      assert run!(totals, team, %{"when" => "2026"}).rows == [[avery.id, 2, 180]]
      assert run!(totals, team, %{"when" => "2026", "tag" => "Rope"}).rows == [[avery.id, 1, 120]]

      %{values: values} = run!(totals, team, %{})

      assert [
               %{name: "when", value: "all", choices: [{"All", "all"} | _]},
               %{name: "tag", choices: [{"All", "all"}, {"Rope", "Rope"}]}
             ] = values

      assert run!("select activity_count('2025', 'all') from members where current", team).rows ==
               [[0]]
    end

    test "says what a field takes" do
      team = team_fixture()

      assert error("select name from members where on_team(5)", team) ==
               "Line 1: Write on_team('2026'): it takes a period: 'all', a year, or '90d'."

      assert error("select name from members where on_team('soon')", team) ==
               "Line 1: Write on_team('2026'): a period is 'all', a year, or '90d'."

      assert error("select activity_count('2026') from members", team) ==
               "Line 1: Write activity_count('2026', 'all'): it takes a period: 'all', a year, or '90d' and a tag's title, or 'all'."
    end
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

  describe "a page (#784)" do
    @page """
    select title, started_at
    from activities
    order by started_at desc
    search title, tags
    switch activity 'Kind'
      option incident 'Incidents' where kind = 'incident'
      option exercise 'Exercises' where kind = 'exercise'
    filter when 'When'
      option past 'Past' where started_at <= NOW
      option future 'Future' where started_at >= NOW sort date
      each year(started_at) where year(started_at) = :when
    filter status 'Status'
      option draft 'Draft' where published = false
    sort date 'Date' started_at
    page 2
    """

    defp page!(team, params, text \\ @page) do
      {:ok, view} = Report.page(text, team, params, @now)
      view
    end

    defp titles(view, team) do
      ids = Enum.map(view.result.rows, &hd/1)
      by_id = Activity |> where([a], a.team_id == ^team.id) |> Repo.all() |> Map.new(&{&1.id, &1})
      Enum.map(ids, &by_id[&1].title)
    end

    setup do
      team = team_fixture()

      for {title, kind, at, tags} <- [
            {"Rope rescue", "exercise", ~U[2026-03-01 18:00:00Z], ["Rope"]},
            {"Lost hiker", "incident", ~U[2026-04-01 18:00:00Z], []},
            {"Swiftwater", "exercise", ~U[2025-05-01 18:00:00Z], ["Water"]},
            {"Night search", "incident", ~U[2026-08-01 18:00:00Z], ["Rope"]}
          ] do
        activity_fixture(team, %{
          title: title,
          activity_kind: kind,
          started_at: at,
          finished_at: DateTime.add(at, 3600),
          tags: tags
        })
      end

      %{team: team}
    end

    test "with nothing picked, the first page of every row, in the query's order", %{team: team} do
      view = page!(team, %{})

      assert titles(view, team) == ["Night search", "Lost hiker"]
      assert view.total == 4
      assert %App.Page{page_number: 1, total_pages: 2, page_size: 2} = view.page
      assert view.sort == "date-"
      assert view.params == %{}

      assert %{name: "activity", picked: "all", tiles: tiles} = view.switch

      assert Enum.map(tiles, &{&1.label, &1.count}) == [
               {"All", 4},
               {"Incidents", 2},
               {"Exercises", 2}
             ]

      assert [%{name: "when", options: options}, %{name: "status", picked: "all"}] = view.filters

      assert options == [
               {"All", "all"},
               {"Past", "past"},
               {"Future", "future"},
               {"2026", "2026"},
               {"2025", "2025"}
             ]
    end

    test "a pick adds its where; tiles count with the search off", %{team: team} do
      view = page!(team, %{"when" => "2026", "q" => "rope", "page" => "1"})

      assert titles(view, team) == ["Night search", "Rope rescue"]
      assert view.params == %{"when" => "2026", "q" => "rope"}
      assert Enum.map(view.switch.tiles, & &1.count) == [3, 2, 1]

      view = page!(team, %{"activity" => "incident", "when" => "past"})
      assert titles(view, team) == ["Lost hiker"]
    end

    test "the search looks in a list's titles, as text", %{team: team} do
      assert titles(page!(team, %{"q" => "wat"}), team) == ["Swiftwater"]
      assert titles(page!(team, %{"q" => "zzz"}), team) == []
    end

    test "a sort from the URL, either way, and an option's sort", %{team: team} do
      assert titles(page!(team, %{"sort" => "date"}), team) == ["Swiftwater", "Rope rescue"]
      assert page!(team, %{"sort" => "date"}).params == %{"sort" => "date"}
      assert page!(team, %{"sort" => "date-"}).params == %{}

      future = page!(team, %{"when" => "future"})
      assert future.sort == "date"
      assert titles(future, team) == ["Night search"]
      assert future.sorts == %{1 => [{"↑", "date"}, {"↓", "date-"}]}
    end

    test "page 2, and a page past the last shows the last", %{team: team} do
      assert titles(page!(team, %{"page" => "2"}), team) == ["Rope rescue", "Swiftwater"]
      assert page!(team, %{"page" => "9"}).page.page_number == 2
    end

    test "a pick that isn't on the menu picks nothing", %{team: team} do
      view = page!(team, %{"when" => "1999", "activity" => "nope"})
      assert view.total == 4
      assert hd(view.filters).picked == "all"
    end

    test "run/4 keeps every row the picks keep, without pages", %{team: team} do
      {:ok, result} = Report.run(@page, team, %{"activity" => "exercise"}, @now)
      assert length(result.rows) == 2
    end

    test "a required filter starts on its value's default", %{team: team} do
      text = """
      select title from activities
      filter year 'Year' required
        each year(started_at) where year(started_at) = :year
      """

      view = page!(team, %{}, text)
      assert view |> titles(team) |> Enum.sort() == ["Lost hiker", "Night search", "Rope rescue"]

      assert [%{picked: "2026", default: "2026", options: [{"2026", _}, {"2025", _}]}] =
               view.filters
    end

    test "a filter's value can feed the query's own where, when it's required", %{team: team} do
      text = """
      select title from activities
      where year(started_at) = :year
      filter year 'Year'
        each year(started_at)
      """

      assert {:error, error} = Report.page(text, team, %{}, @now)

      assert Error.text(error) ==
               "Line 3: Write required after filter year: the query reads :year, so it always needs a pick."

      required = String.replace(text, "'Year'", "'Year' required")
      {:ok, view} = Report.page(required, team, %{"year" => "2025"}, @now)

      assert titles(view, team) == ["Swiftwater"]
    end

    test "a grouped report counts and pages its groups", %{team: team} do
      text = """
      select kind, count(id)
      from activities
      group by kind
      order by count(id) desc
      switch status 'Status'
        option draft 'Draft' where published = false
      page 1
      """

      view = page!(team, %{}, text)
      assert view.total == 2
      assert Enum.map(view.switch.tiles, & &1.count) == [2, 2]
      assert length(view.result.rows) == 1
    end

    test "a mistake names its line and the part of the page it's in", %{team: team} do
      text = """
      select title, started_at
      from activities
      order by started_at desc
      filter status 'Status'
        option draft 'Draft' where publshed = false
        option published 'Published' where published = true
      page 50
      """

      assert {:error, error} = Report.page(text, team, %{}, @now)

      assert Error.text(error) ==
               "Line 5, option draft: activities has no field publshed. Did you mean published?"

      assert {:error, error} = Report.run(text, team, %{}, @now)
      assert error.part == "option draft"

      assert error("select title from activities\nsearch nope", team) =~
               "Line 2, search: activities has no field nope."

      assert error("select title from activities\nsort when 'When' finished_at", team) ==
               "Line 2, sort when: Label it like the column it sorts, one of 'Activity', or show its field."

      assert error("select title from activities\nfilter f 'F'\n  each started_at", team) ==
               "Line 3, filter f: Write each with a field it can list, such as year(started_at), kind, or member.groups."
    end
  end
end
