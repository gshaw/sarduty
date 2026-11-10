defmodule App.ReportTest do
  use App.DataCase, async: true

  import App.DataFixtures
  import ExUnit.CaptureLog

  alias App.Model.Activity
  alias App.Model.Member
  alias App.Operation.CountTaxCreditHours
  alias App.Report
  alias App.Report.Catalog
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Parser
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

          assert field.type in [
                   :text,
                   :number,
                   :hours,
                   :km,
                   :money,
                   :date,
                   :bool,
                   :list,
                   :choice,
                   :place
                 ] or
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

        assert {:ok, %{rows: rows}} =
                 Report.run("select #{names} from #{subject.name}", team, %{}, @now)

        assert length(rows) == if(subject.name == "team", do: 1, else: 0)
      end
    end

    # A source selects only the columns a report reads, with only their joins (#784), so a
    # column whose join is missing from its `needs` fails here, alone, and not beside others.
    test "every field runs alone" do
      team = team_fixture()

      for subject <- Catalog.subjects(), field <- subject.fields, field.args == [] do
        assert {:ok, %{rows: rows}} =
                 Report.run("select #{field.name} from #{subject.name}", team, %{}, @now),
               "#{subject.name}.#{field.name} does not run alone"

        assert length(rows) == if(subject.name == "team", do: 1, else: 0)
      end
    end

    # A count's rows are the where's, so it leaves out the joins only the select needs:
    # Members' tiles don't add up everyone's attendance (#784).
    test "a count reads only the columns its where reads" do
      context = Context.new(team_fixture(), @now)
      {:ok, query} = Parser.parse("select name, last_attended from members where current")

      {:ok, {sql, _params}} = Compiler.count(query, context)
      refute IO.iodata_to_binary(sql) =~ "attendances"

      {:ok, {sql, _params}} = Compiler.counts(query, [nil], context)
      refute IO.iodata_to_binary(sql) =~ "attendances"

      {:ok, plan} = Compiler.compile(query, context)
      assert IO.iodata_to_binary(plan.sql) =~ "attendances"
    end

    test "reports leave out emergency contacts, and contact details are team admins'" do
      team = team_fixture()

      assert error("select emergency_contact from members", team) ==
               "Line 1: Reports leave out emergency contacts. members has no field emergency_contact."

      assert error("select member.phone from attendance", team) =~ "Use mobile."
      assert error("select coordinate from activities", team) =~ "Use place."
      assert {:ok, _plan} = Report.check("select name, email, mobile, address from members", team)

      assert {:error, error} =
               Report.page("select name, email from members", team, %{}, @now, team_admin?: false)

      assert Error.text(error) =~ "members has no field email"
    end

    test "ID card fields give the live card, blank with none, for team admins on a team with cards" do
      team = team_fixture()
      avery = member_fixture(team, %{name: "Avery Chen"})
      blake = member_fixture(team, %{name: "Blake Diaz"})
      member_fixture(team, %{name: "Casey Ng"})

      member_card_fixture(avery, %{
        code: "AAAA222222",
        revoked_at: ~U[2026-04-01 17:00:00.000000Z]
      })

      member_card_fixture(avery, %{
        code: "K7Q4M2XA9H",
        inserted_at: ~U[2026-05-01 17:00:00.000000Z]
      })

      member_card_fixture(blake, %{
        code: "BBBB333333",
        revoked_at: ~U[2026-04-01 17:00:00.000000Z]
      })

      text = "select name, id_card, id_card_link, id_card_issued from members order by name"
      result = run!(text, team)

      assert [
               [_avery, "K7Q4M-2XA9H", link, ~U[2026-05-01 17:00:00Z]],
               [_blake, nil, nil, nil],
               [_casey, nil, nil, nil]
             ] = result.rows

      assert link == Web.VerifyHost.url() <> "/K7Q4M-2XA9H"
      assert {:ok, _plan} = Report.check("select name from members where id_card is null", team)

      assert {:error, error} = Report.page(text, team, %{}, @now, team_admin?: false)
      assert Error.text(error) =~ "members has no field id_card"

      assert error(text, team_fixture(%{id_cards_enabled: false})) =~
               "members has no field id_card"
    end

    test "a place compares only with is null" do
      team = team_fixture()

      assert {:ok, _plan} =
               Report.check("select title, place from activities where place is not null", team)

      assert error("select title from activities where place = '49,-123'", team) ==
               "Line 1: Compare place only with is null or is not null."
    end

    test "contact details and places read their columns, a blank or 0,0 place as null" do
      team = team_fixture()

      member_fixture(team, %{
        name: "Avery Chen",
        email: "avery@example.com",
        phone: "604-555-0101",
        address: "1 Example Road"
      })

      activity_fixture(team, %{
        title: "Night search",
        coordinate: "49.30000,-123.10000",
        address: "Cedar Creek"
      })

      activity_fixture(team, %{title: "Hall night", coordinate: Activity.null_island()})

      {:ok, result} =
        Report.run("select name, email, mobile, address from members", team, %{}, @now)

      assert [[_id, "avery@example.com", "604-555-0101", "1 Example Road"]] = result.rows

      {:ok, result} =
        Report.run("select title, address, place from activities order by title", team, %{}, @now)

      assert Enum.map(result.rows, fn [_id, address, place] -> {address, place} end) ==
               [{"123 Main St", nil}, {"Cedar Creek", "49.30000,-123.10000"}]
    end
  end

  test "an activity's description reads as text, not D4H's HTML, and still filters (#970)" do
    team = team_fixture()

    activity_fixture(team, %{
      title: "Port Mann",
      description: "<p>Requested by Surrey Police &amp; RCMP.</p><p>Stood down.</p>"
    })

    {:ok, result} =
      Report.run(
        "select title, description from activities where description contains 'Surrey'",
        team,
        %{},
        @now
      )

    assert [[_id, "Requested by Surrey Police & RCMP.\nStood down."]] = result.rows
  end

  # A report's rows are plain lists, with no redact: true, so they hold contact details
  # in the clear (#827). Only SQLite's message reaches the log.
  test "nothing in the report code logs rows" do
    for path <- ["lib/app/report.ex" | Path.wildcard("lib/app/report/**/*.ex")],
        line <- path |> File.read!() |> String.split("\n"),
        line =~ "Logger." do
      assert line =~ "Exception.message(reason)", "#{path} logs: #{String.trim(line)}"
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
                 Runner.run(%Plan{sql: "SELECT 1 GROUP BY", params: []}, "Etc/UTC", App.Repo)
      end)

    assert log =~ "Report could not run: incomplete input"

    slow =
      "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 1000000000) SELECT count(*) FROM c"

    capture_log(fn ->
      assert {:error, %Error{message: "Narrow the report with where" <> _}} =
               Runner.run(%Plan{sql: slow, params: []}, "Etc/UTC", App.Repo)
    end)
  end

  # Each repo's queries come with its own telemetry event, in the process that ran them.
  # App.SampleRepoTest checks a sample run the other way.
  test "a real team's run never reads Coast Range SAR's database" do
    team = team_fixture()
    activity_fixture(team)
    id = "report-test-#{inspect(self())}"
    events = [[:app, :repo, :query], [:app, :sample_repo, :query]]
    :telemetry.attach_many(id, events, &__MODULE__.forward/4, self())
    on_exit(fn -> :telemetry.detach(id) end)

    assert {:ok, _result} =
             Report.run("select title, attended_count from activities", team, %{}, @now)

    assert {:ok, _view} = Report.page("select name, groups from members page 10", team, %{}, @now)

    assert_received {:query, [:app, :repo, :query]}
    refute_received {:query, [:app, :sample_repo, :query]}
  end

  @doc false
  def forward(event, _measurements, _metadata, test),
    do: if(self() == test, do: send(test, {:query, event}))

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

  test "activities report Enough at, Full at, and sign-ups as the badges count them" do
    team = team_fixture()

    [avery, blake, casey] =
      for name <- ~w(Avery Blake Casey), do: member_fixture(team, %{name: name})

    stranger = member_fixture(team_fixture())

    short =
      team
      |> activity_fixture(%{title: "Short", started_at: ~U[2026-07-01 18:00:00Z]})
      |> Ecto.Changeset.change(enough_at: 3, full_at: 5)
      |> Repo.update!()

    open = activity_fixture(team, %{title: "Open", started_at: ~U[2026-07-02 18:00:00Z]})

    attendance_fixture(short, avery)
    attendance_fixture(short, avery, %{status: "requested"})
    attendance_fixture(short, blake)
    attendance_fixture(short, casey, %{status: "absent"})
    attendance_fixture(short, stranger)

    result =
      run!(
        "select title, signed_up_count, enough_at, full_at from activities order by title",
        team
      )

    assert result.rows == [[open.id, 0, nil, nil], [short.id, 2, 3, 5]]

    assert run!("select title from activities where signed_up_count < enough_at", team).rows ==
             [[short.id]]
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

  # A Saturday evening in Vancouver is a Sunday in UTC: each part reads the local time.
  test "date, months_since, day_of_week, and hour read the team's day (#826)" do
    team = team_fixture()
    activity_fixture(team, %{started_at: ~U[2026-05-03 02:30:00Z]})

    query =
      "select date(started_at), months_since(started_at), day_of_week(started_at), hour(started_at) from activities"

    assert run!(query, team).rows == [[~D[2026-05-02], 1, 6, 19]]
    assert run!("select id from activities where months_since(started_at) < 1", team).rows == []

    assert [[_id]] =
             run!("select id from activities where months_since(started_at) < 2", team).rows

    result =
      run!(
        "select day_of_week(started_at), count(id) from activities group by day_of_week(started_at)",
        team
      )

    assert [%{type: :weekday}, _] = result.columns
  end

  test "sum of a condition counts the rows it holds for (#826)" do
    team = team_fixture()
    member_fixture(team, %{joined_at: ~U[2026-02-01 12:00:00Z]})
    member_fixture(team, %{joined_at: ~U[2020-02-01 12:00:00Z]})

    assert run!("select count(id), sum(joined_at = THIS_YEAR) from members", team).rows == [
             [2, 1]
           ]
  end

  describe "format (#804)" do
    test "each field draws its own cell, and format picks another" do
      team = team_fixture()
      activity_fixture(team)

      columns =
        run!("select title, kind, started_at, attended_hours from activities", team).columns

      assert Enum.map(columns, & &1.format) == ["link", "marker", "date", "duration"]

      text = """
      select title, kind, started_at, attended_hours, attended_count
      from activities
      format title as text, kind as text, started_at as month, attended_hours as hours
      """

      assert Enum.map(run!(text, team).columns, & &1.format) ==
               ["text", "text", "month", "hours", nil]
    end

    test "a count of a record is a number, with no format of its own" do
      team = team_fixture()
      text = "select activity.kind, count(member) from attendance group by activity.kind"
      assert Enum.map(run!(text, team).columns, & &1.format) == ["marker", nil]
    end

    test "says which formats a column takes" do
      team = team_fixture()

      assert error("select started_at from activities format started_at as week", team) =~
               "Show started_at as date, date_long, date_time, month, time, or days_ago."

      assert error("select ref_id from activities format ref_id as text", team) =~
               "Take out the format: ref_id shows one way."

      assert error("select title from activities format started_at as month", team) =~
               "Add started_at to select, or take its format out."

      assert error("select title from activities format title text", team) =~
               "Write as and a format after title"
    end
  end

  # Toronto keeps daylight saving time, so one fixed offset would get one of these wrong.
  test "local dates follow daylight saving time" do
    team = team_fixture(%{timezone: "America/Toronto"})
    # 11:30 pm on June 30 (EDT) and on December 31 (EST).
    june = activity_fixture(team, %{started_at: ~U[2026-07-01 03:30:00Z]})
    december = activity_fixture(team, %{started_at: ~U[2026-01-01 04:30:00Z]})

    assert run!(
             "select year(started_at), month(started_at) from activities order by started_at",
             team
           ).rows ==
             [[2025, 12], [2026, 6]]

    # A year compared with one is a range of the stored time (#784), with the same edge.
    assert run!("select id from activities where year(started_at) = 2025", team).rows ==
             [[december.id]]

    assert run!("select id from activities where year(started_at) > 2025", team).rows ==
             [[june.id]]

    assert run!("select id from activities where year(started_at) = :year", team, %{
             "year" => "2025"
           }).rows == [[december.id]]
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

    test "Activities' Last 30 days, Missing fields, and chores" do
      team = team_fixture()
      now = @now
      two_days_ago = DateTime.add(now, -2, :day)

      this_week =
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

      assert ids("select id from activities where recent = true", team) ==
               Enum.sort([this_week.id, recent.id])

      assert ids("select id from activities where missing_required_fields", team) == [missing.id]
      assert ids("select id from activities where chore = true", team) == [chore.id]

      assert run!("select duration from activities where chore = true", team).rows == [[75]]

      assert run!("select duration from activities where id = #{this_week.id}", team).rows == [
               [60]
             ]
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

  # The letter list's counts, so a report and a letter never disagree (#918).
  test "tax_credit_hours is CountTaxCreditHours, each year as its letter counts it" do
    team = team_fixture()
    avery = member_fixture(team, %{name: "Avery Chen"})
    blake = member_fixture(team, %{name: "Blake Diaz"})

    # Avery's two overlapping rows count once, and primary wins the overlap.
    primary =
      activity_fixture(team, %{
        started_at: ~U[2025-03-01 17:00:00Z],
        finished_at: ~U[2025-03-01 20:00:00Z]
      })

    secondary =
      activity_fixture(team, %{
        tags: ["Secondary Hours"],
        started_at: ~U[2025-03-01 19:00:00Z],
        finished_at: ~U[2025-03-01 21:00:00Z]
      })

    # New Year's Eve in Vancouver is 2025's, though it's 2026 in UTC.
    eve =
      activity_fixture(team, %{
        started_at: ~U[2026-01-01 05:00:00Z],
        finished_at: ~U[2026-01-01 07:00:00Z]
      })

    this_year =
      activity_fixture(team, %{
        started_at: ~U[2026-02-01 17:00:00Z],
        finished_at: ~U[2026-02-01 18:30:00Z]
      })

    untagged = activity_fixture(team, %{tags: ["Rope"], started_at: ~U[2026-02-02 17:00:00Z]})

    for activity <- [primary, secondary, eve, this_year, untagged],
        do: attendance_fixture(activity, avery)

    attendance_fixture(this_year, blake)

    text =
      "select member, year, primary, secondary, total from tax_credit_hours order by year desc"

    rows = run!(text <> ", member.name", team).rows

    expected =
      for year <- [2026, 2025],
          {member_id, hours} <-
            team |> CountTaxCreditHours.call(year, nil, @now) |> Enum.sort_by(&elem(&1, 0)) do
        [member_id, year, hours.primary_minutes, hours.secondary_minutes, hours.total_minutes]
      end

    assert rows == expected

    assert rows == [
             [avery.id, 2026, 90, 0, 90],
             [blake.id, 2026, 90, 0, 90],
             [avery.id, 2025, 300, 60, 360]
           ]

    assert run!(
             "select member, sum(total) from tax_credit_hours group by member order by member",
             team
           ).rows ==
             [[avery.id, 450], [blake.id, 90]]

    # A letter counts only its member's year, and gets the same row the team's count has.
    all = CountTaxCreditHours.by_year(team, @now)

    for member <- [avery, blake], year <- [2025, 2026] do
      assert CountTaxCreditHours.by_year(team, @now, App.Repo, {member.id, year}) ==
               Enum.filter(all, &(&1.member_id == member.id and &1.year == year))
    end
  end

  # cspell:ignore Łukasz Tomáš Dvořák
  test "team is the team's one row, and organization its organization's" do
    team =
      %{legal_name: "Łukasz Valley Search and Rescue Society"}
      |> team_fixture()
      |> Ecto.Changeset.change(
        authorized_by_name: "Tomáš Dvořák",
        authorized_by_title: "President"
      )
      |> Repo.update!()

    text = "select name, legal_name, mailing_address, signer, signer_title from team"

    assert run!(text, team).rows == [
             [
               team.name,
               "Łukasz Valley Search and Rescue Society",
               "123 Main St",
               "Tomáš Dvořák",
               "President"
             ]
           ]

    assert run!("select name from organization", team).rows == []

    organization = organization_fixture([team], %{website: "https://example.org"})
    other = team_fixture()
    organization_fixture([other])

    assert run!("select name, short_name, website from organization", team).rows == [
             [organization.name, "EXA", "https://example.org"]
           ]
  end

  test "reports never read the signer's signature or an organization's logo" do
    team = team_fixture()

    for {subject, field} <- [{"team", "signature"}, {"organization", "logo"}] do
      assert {:error, _error} = Report.check("select #{field} from #{subject}", team)
    end

    columns = for subject <- Catalog.subjects(), field <- subject.fields, do: field.column
    refute :signature in columns
    refute :logo in columns
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

    test "a pick adds its where; tiles count the search too (#935)", %{team: team} do
      view = page!(team, %{"when" => "2026", "q" => "rope", "page" => "1"})

      assert titles(view, team) == ["Night search", "Rope rescue"]
      assert view.params == %{"when" => "2026", "q" => "rope"}
      assert Enum.map(view.switch.tiles, & &1.count) == [2, 1, 1]

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

  describe "who reads it, several picks, and menus from values (#784)" do
    @members """
    select name, activity_count(:when, :tag)
    from members
    where on_team(:when) and in_group(:group)
    order by name
    switch standing 'Standing' default current
      option current 'Not retired' where current = true
      option active 'Active' where standing = 'active'
      option away 'Away' where standing = 'away'
      option retired 'Retired' where standing = 'retired'
    filter when 'Period' default THIS_YEAR
    filter group 'Group'
    filter tag 'Tag' more
    filter items 'Items'
      option held 'Holds some' where holds_items = true
    """

    defp names(view) do
      ids = Enum.map(view.result.rows, &hd/1)
      Member |> where([m], m.id in ^ids) |> Repo.all() |> Enum.map(& &1.name) |> Enum.sort()
    end

    defp tiles(view), do: Map.new(view.switch.tiles, &{&1.value, &1.count})

    setup do
      team = team_fixture(%{timezone: "America/Vancouver"})
      tag_fixture(team, "Rope")
      callout = group_fixture(team, %{title: "Callout"})
      joined = ~U[2020-01-01 00:00:00Z]

      avery = member_fixture(team, %{name: "Avery Chen", joined_at: joined})
      blake = member_fixture(team, %{name: "Blake Morrison", joined_at: joined})

      casey =
        member_fixture(team, %{
          name: "Casey Dhillon",
          joined_at: joined,
          left_at: ~U[2025-03-01 00:00:00Z]
        })

      away_period_fixture(blake, ~D[2026-06-01], ~D[2026-06-30])
      group_member_fixture(callout, avery)

      rope =
        activity_fixture(team, %{
          tags: ["Rope"],
          started_at: ~U[2026-03-01 18:00:00Z],
          finished_at: ~U[2026-03-01 20:00:00Z]
        })

      attendance_fixture(rope, avery, %{duration_in_minutes: 120})

      %{team: team, callout: callout, avery: avery, blake: blake, casey: casey}
    end

    test "a team admin sees Away; a member reads it as Active and loses its option", %{
      team: team
    } do
      {:ok, admin} = Report.page(@members, team, %{}, @now)

      assert tiles(admin) == %{
               "all" => 2,
               "current" => 2,
               "active" => 1,
               "away" => 1,
               "retired" => 0
             }

      assert Enum.map(admin.filters, & &1.name) == ~w(when group tag items)

      {:ok, member} = Report.page(@members, team, %{}, @now, team_admin?: false)
      assert tiles(member) == %{"all" => 2, "current" => 2, "active" => 2, "retired" => 0}
      assert Enum.map(member.filters, & &1.name) == ~w(when group tag)

      # A member's URL that names what they can't see starts where the page starts.
      {:ok, member} =
        Report.page(@members, team, %{"standing" => "away", "items" => "held"}, @now,
          team_admin?: false
        )

      assert member.switch.picked == "current"
      assert names(member) == ["Avery Chen", "Blake Morrison"]
      assert member.params == %{}
    end

    test "several picks OR their wheres, and the menu names them", %{team: team} do
      {:ok, view} = Report.page(@members, team, %{"standing" => "active,away"}, @now)

      assert names(view) == ["Avery Chen", "Blake Morrison"]
      assert view.switch.picked == "active,away"
      assert view.params == %{"standing" => "active,away"}
      assert {"Active or away", "active,away"} in view.switch.options
      assert hd(view.switch.options) == {"All", "all"}

      {:ok, view} = Report.page(@members, team, %{"standing" => "away,active"}, @now)
      assert view.switch.picked == "active,away"

      {:ok, view} = Report.page(@members, team, %{"standing" => "active,nope"}, @now)
      assert view.switch.picked == "current"
    end

    test "a filter without options shows its value's menu and feeds its fields", %{
      team: team,
      callout: callout,
      avery: avery
    } do
      {:ok, view} = Report.page(@members, team, %{}, @now)
      [period, group, tag, _items] = view.filters

      assert %{picked: "2026", default: "2026"} = period
      assert [{"All", "all"}, {"Last 30 days", "30d"} | _] = period.options
      assert {"2026", "2026"} in period.options
      assert group.options == [{"All", "all"}, {"Callout", Integer.to_string(callout.id)}]
      assert %{picked: "all", more: true, options: [{"All", "all"}, {"Rope", "Rope"}]} = tag

      {:ok, view} = Report.page(@members, team, %{"when" => "all"}, @now)
      assert names(view) == ["Avery Chen", "Blake Morrison"]

      {:ok, view} =
        Report.page(@members, team, %{"when" => "all", "standing" => "all"}, @now)

      assert names(view) == ["Avery Chen", "Blake Morrison", "Casey Dhillon"]

      {:ok, view} = Report.page(@members, team, %{"group" => "#{callout.id}"}, @now)
      assert view.result.rows == [[avery.id, 1]]
      assert view.params == %{"group" => "#{callout.id}"}

      {:ok, view} = Report.page(@members, team, %{"tag" => "Rope", "when" => "30d"}, @now)
      assert Enum.map(view.result.rows, &List.last/1) == [0, 0]
    end

    test "in_group takes a group's title", %{team: team, avery: avery} do
      assert ids("select id from members where in_group('callout')", team) == [avery.id]

      assert error("select id from members where in_group('Nope')", team) ==
               "Line 1: Write in_group('Callout'): there is no group 'Nope'."
    end

    test "ids/4 keeps the rows the picks keep, by id", %{team: team, avery: avery, blake: blake} do
      assert Report.ids(@members, team, %{"standing" => "active,away"}, @now) ==
               {:ok, Enum.sort([avery.id, blake.id])}

      assert Report.ids(@members, team, %{"items" => "held"}, @now) == {:ok, []}
    end

    test "a filter with no choices must name a value a field takes", %{team: team} do
      text = "select name from members\nfilter period 'Period'"

      assert {:error, error} = Report.page(text, team, %{}, @now)

      assert Error.text(error) ==
               "Line 2: Write an option or each under filter period, or pass :period to a field, such as on_team(:period)."
    end
  end
end
