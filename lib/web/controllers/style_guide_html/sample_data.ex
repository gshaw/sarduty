defmodule Web.StyleGuideHTML.SampleData do
  @moduledoc false

  alias App.Model.Team
  alias App.ViewData.Milestones
  alias Service.Format
  alias Web.Components.ActivityMap

  # cspell:ignore Tremblay exsss
  # Made-up rows for the style guide, shaped like the app's pages.

  def letters do
    Enum.map(
      [
        {101, "Avery Chen", "avery@example.com", {212, 30}, {18, 0}, "TCL-2025-014"},
        {117, "Blake Morrison", "blake@example.com", {198, 15}, {4, 45}, nil},
        {123, "Casey Dhillon", "casey@example.com", {156, 0}, {62, 30}, "TCL-2025-015"},
        {131, "Devon Okafor", "devon@example.com", {88, 45}, {12, 15}, nil},
        {152, "Finley Tremblay", "finley@example.com", {41, 0}, {9, 30}, nil}
      ],
      &letter_row/1
    )
  end

  # Hours as `{hours, minutes}`, shown the way the letters page shows them.
  defp letter_row({id, name, email, primary, secondary, letter}) do
    primary = minutes(primary)
    secondary = minutes(secondary)

    %{
      id: id,
      name: name,
      email: email,
      primary: Format.duration(primary),
      secondary: Format.duration(secondary),
      total: Format.duration(primary + secondary),
      letter: letter
    }
  end

  defp minutes({hours, minutes}), do: hours * 60 + minutes

  # The activity filters with When set to a year, for the filter bar.
  def sample_filters,
    do:
      Phoenix.Component.to_form(
        %{"q" => "", "kind" => "all", "when" => "2025", "hours" => "all", "status" => "all"},
        as: :demo
      )

  def sample_filter_page,
    do: %App.Page{entries: [], page_number: 1, page_size: 50, total_entries: 212, total_pages: 5}

  def sample_kinds,
    do: [{"All", "all"}, {"Incident", "incident"}, {"Exercise", "exercise"}, {"Event", "event"}]

  def sample_hours,
    do: [{"All", "all"}, {"Primary", "primary"}, {"Secondary", "secondary"}, {"None", "none"}]

  def sample_statuses, do: [{"All", "all"}, {"Draft", "draft"}, {"Published", "published"}]

  def sample_whens,
    do: [{"All", "all"}, {"Current", "current"}, {"2025", "2025"}, {"2024", "2024"}]

  # Page 2 of a long activity list, for the pagination example.
  def sample_page do
    %App.Page{entries: [], page_number: 2, page_size: 50, total_entries: 1912, total_pages: 39}
  end

  def sample_user, do: %App.Accounts.User{id: 0, email: "avery@example.com", is_admin: false}

  # For the team switcher: Avery is a team admin and a member on Squamish, and only a
  # member on Pemberton.
  def sample_managed_teams, do: [sample_team()]

  def sample_member do
    %App.Model.Member{id: 0, name: "Avery Lee", team: sample_team()}
  end

  def sample_member_logins do
    pemberton = %App.Model.Team{id: 1, name: "Pemberton SAR", subdomain: "pemberton"}
    [sample_member(), %App.Model.Member{id: 1, name: "Avery Lee", team: pemberton}]
  end

  # Squamish's space on its activities, for a team admin who is a member, with 2 proposed
  # changes waiting.
  def sample_nav_area, do: Web.Navigation.area("/teams/squamish/activities", sample_team())

  def sample_nav_sections,
    do:
      Web.Navigation.sections(sample_nav_area(), "/teams/squamish/activities",
        team_admin?: true,
        member?: true,
        proposed_changes: 2
      )

  def sample_team do
    %App.Model.Team{
      id: 0,
      name: "Squamish SAR",
      subdomain: "squamish",
      timezone: "America/Vancouver"
    }
  end

  # Activities as App.Model.Activity, so the guide renders them with the app's own table.
  # Times are UTC; the table shows them in Vancouver time.
  def activities do
    [
      {1, "25-0412", "Missing hiker, Stawamus Chief", "incident", "2025-09-28T21:05:00Z", 505,
       ["Primary Hours"], "25-0412", true,
       "Hiker overdue on the Chief's back trail. Found at 21:10 and walked out with the team."},
      {2, "25-0409", "Rope rescue, Murrin Park", "exercise", "2025-09-24T16:00:00Z", 180,
       ["Secondary Hours", "Rope"], nil, true, nil},
      {3, "25-0405", "Squamish Days first aid booth", "event", "2025-09-21T17:00:00Z", 240,
       ["Secondary Hours"], nil, true, nil},
      {4, "25-0398", "Overdue kayaker, Howe Sound", "incident", "2025-09-17T02:30:00Z", 225,
       ["Primary Hours", "Marine"], "25-0398", true, nil},
      {5, "25-0396", "Team meeting", "event", "2025-09-11T02:00:00Z", 90, [], nil, false, nil}
    ]
    |> Enum.map(fn {id, ref_id, title, kind, started, minutes, tags, number, published, about} ->
      {:ok, started_at, 0} = DateTime.from_iso8601(started)

      %App.Model.Activity{
        id: id,
        ref_id: ref_id,
        title: title,
        activity_kind: kind,
        started_at: started_at,
        finished_at: DateTime.add(started_at, minutes * 60),
        tags: tags,
        tracking_number: number,
        is_published: published,
        description: about
      }
    end)
  end

  # A member's 2025 letter, for the member letter example. Its download goes nowhere.
  def letter do
    %App.Model.TaxCreditLetter{id: 0, year: 2025, primary_minutes: 8820, secondary_minutes: 1500}
  end

  # One member's milestones, newest first, as Milestones.build/5 makes them.
  def milestones do
    [
      %{
        kind: :incidents,
        count: 25,
        on: ~D[2026-09-28],
        activity: %{title: "Missing hiker, Stawamus Chief"}
      },
      %{
        kind: :hours,
        count: 500,
        on: ~D[2026-09-24],
        activity: %{title: "Rope rescue, Murrin Park"}
      },
      %{kind: :years, count: 5, on: ~D[2026-05-14], activity: nil}
    ]
  end

  @every_milestone_up_to %{hours: 5000, years: 30, incidents: 500}

  # Every milestone of a kind, newest first, up to a little past what a long-serving
  # member reaches: hours to 5,000, years to 30, incidents to 500. The lines come from
  # Milestones.lines/2, so this page shows what the app does.
  def every_milestone(kind) do
    activity =
      case kind do
        :hours -> %{title: "Training night: navigation"}
        :incidents -> %{title: "Missing hiker, Stawamus Chief"}
        :years -> nil
      end

    kind
    |> Milestones.lines(@every_milestone_up_to[kind])
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {count, i} ->
      %{kind: kind, count: count, on: Date.add(~D[2026-06-01], -200 * i), activity: activity}
    end)
  end

  # One member's qualifications, soonest expiry first, for the table's greyed rows.
  def qualification_rows do
    [
      %{id: 1, title: "Standard First Aid", expires: "Dec 5, 2026", days: 45, expired?: false},
      %{
        id: 2,
        title: "Rope Rescue Operations",
        expires: "Sep 30, 2027",
        days: nil,
        expired?: false
      },
      %{id: 3, title: "ICS 100", expires: nil, days: nil, expired?: false},
      %{
        id: 4,
        title: "Swiftwater Awareness",
        expires: "Expired Sep 30, 2024",
        days: nil,
        expired?: true
      }
    ]
  end

  # Members by standing, for the table's row groups.
  def member_groups do
    [
      %{
        id: "active",
        title: "Active",
        rows: [
          %{id: 1, name: "Casey Dhillon", last_attended: "Oct 14"},
          %{id: 2, name: "Morgan Lee", last_attended: "Oct 2"}
        ]
      },
      %{id: "away", title: "Away", rows: [%{id: 3, name: "Sam Okafor", last_attended: "Jun 21"}]},
      %{
        id: "retired",
        title: "Retired",
        muted: true,
        rows: [
          %{id: 4, name: "Jordan Price", last_attended: "Mar 3, 2024"}
        ]
      }
    ]
  end

  # A group's rules, its editor's rows, and its menu, in the shapes
  # Web.Components.GroupRule takes.
  def rule_sentence_rules do
    [
      %{kind: :in, names: [{:group, "GSAR Qualified Callout"}, {:group, "MIT Callout"}]},
      %{kind: :standing, names: [{:standing, "Active"}]}
    ]
  end

  def rule_rows do
    [
      %{
        id: 1,
        kind: :in,
        names: "GSAR Qualified Callout or MIT Callout",
        path: "#",
        confirm: nil
      },
      %{id: 2, kind: :standing, names: "Active", path: "#", confirm: nil}
    ]
  end

  # Enough qualifications that scrolling a select to find one is slow, as on a real team.
  def qualification_options do
    Enum.with_index(
      [
        "07+ Hour First Aid Training or Equivalent",
        "16+ Hour First Aid Training or Equivalent",
        "70+ Hour First Aid Training or Equivalent",
        "Avalanche Skills Training 1",
        "Avalanche Skills Training 2",
        "Chainsaw Bucking Operations",
        "Criminal Record Check",
        "Driver Truck",
        "Driver UTV",
        "First Aid Instructor",
        "Ground Search Team Leader (GSTL)",
        "Ground Search and Rescue (GSAR)",
        "Ham Radio",
        "ICS 100",
        "ICS 200",
        "Mountain Rescue 1",
        "Occupational First Aid Level 1",
        "Occupational First Aid Level 2",
        "Occupational First Aid Level 3",
        "Remote First Aid",
        "Rope Rescue Operations",
        "Rope Rescue Technician",
        "Swiftwater Rescue Technician",
        "Wilderness First Responder"
      ],
      1
    )
  end

  def rule_options,
    do: [
      {"Groups", [{"Rope Rescue", "group:3"}, {"Swiftwater Team", "group:4"}]},
      {"Endorsements", [{"First Aid", "endorsement:1"}, {"Swiftwater 1", "endorsement:2"}]},
      {"Standing", [{"Away", "standing:away"}, {"Not a person", "standing:not_a_person"}]}
    ]

  # Team settings after a failed save: the app's own changeset, with a blank name and an
  # email that isn't one.
  def settings_form do
    team = %{
      sample_team()
      | lat: 49.70161,
        lng: -123.15583,
        mailing_address: "PO Box 123\nSquamish BC V8B 0A1"
    }

    params = %{
      "name" => "",
      "authorized_by_name" => "Avery Chen",
      "authorized_by_email" => "avery at example"
    }

    team
    |> Team.build_settings_changeset(params)
    |> Map.put(:action, :update)
    |> Phoenix.Component.to_form(as: "form", id: "settings")
  end

  # Charts. Made-up numbers with a summer peak, as a coastal team's year looks.
  @months ~w(Nov Dec Jan Feb Mar Apr May Jun Jul Aug Sep Oct)
  @incidents [5, 4, 3, 4, 5, 6, 8, 11, 15, 14, 9, 2]
  @exercises [6, 5, 5, 6, 6, 5, 6, 5, 4, 5, 6, 2]
  @events [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0]

  def chart_columns do
    [@months, @incidents, @exercises, @events]
    |> Enum.zip()
    |> Enum.map(fn {month, i, x, e} ->
      %{
        label: month,
        values: %{incident: i, exercise: x, event: e},
        tip: "#{month}\n#{i} incidents\n#{x} exercises\n#{e} events"
      }
    end)
  end

  def chart_hours do
    [
      %{
        key: :primary,
        label: "2025",
        values: [180, 390, 640, 900, 1210, 1580, 2140, 2830, 3300, nil, nil, nil]
      },
      %{
        key: :compare,
        label: "2024",
        values: [150, 320, 560, 820, 1100, 1460, 1910, 2480, 2950, 3240, 3460, 3700]
      }
    ]
  end

  def chart_members do
    [
      %{label: "Avery Chen", value: 212, text: "212h"},
      %{label: "Casey Dhillon", value: 188, text: "188h"},
      %{label: "Devon Okafor", value: 161, text: "161h"},
      %{label: "Jordan Larsen", value: 140, text: "140h"},
      %{label: "Riley Moreau", value: 97, text: "97h"}
    ]
  end

  # A year of days from Oct 1, 2024: weekly Wednesday exercises, and incidents that pick up
  # in summer and on weekends. Seeded, so the guide looks the same on every load.
  def chart_days do
    :rand.seed(:exsss, {1, 2, 3})
    first = ~D[2024-10-01]

    Enum.map(0..364, fn offset ->
      date = Date.add(first, offset)
      summer = if date.month in 6..9, do: 2, else: 1
      weekend = if Date.day_of_week(date) in [6, 7], do: 2, else: 1
      exercise = if Date.day_of_week(date) == 3, do: 1, else: 0
      incidents = Enum.count(1..(summer * weekend), fn _ -> :rand.uniform() < 0.18 end)
      {date, exercise + incidents}
    end)
  end

  def chart_week do
    :rand.seed(:exsss, {4, 5, 6})

    for day <- 1..7, do: for(hour <- 0..23, do: sample_count(day, hour))
  end

  # More in the afternoon and evening, and twice as many at weekends.
  defp sample_count(day, hour) do
    daytime = if hour in 12..21, do: 3, else: 1
    weekend = if day in [6, 7], do: 2, else: 1
    Enum.count(1..(daytime * weekend), fn _ -> :rand.uniform() < 0.3 end)
  end

  # Made-up activities around Squamish, at real landmarks.
  def chart_map do
    points = [
      {49.6833, -123.1450, :incident, "Missing hiker, Stawamus Chief"},
      {49.6890, -123.1380, :incident, "Injured climber, Stawamus Chief"},
      {49.7760, -123.1180, :incident, "Lost child, Alice Lake"},
      {49.8000, -123.0600, :incident, "Injured biker, Diamond Head"},
      {49.5600, -123.2500, :incident, "Overdue kayaker, Howe Sound"},
      {49.9333, -123.0300, :incident, "Stranded hikers, Garibaldi Lake"},
      {49.6450, -123.2050, :exercise, "Rope rescue, Murrin Park"},
      {49.7016, -123.1558, :exercise, "Night navigation"},
      {49.7400, -123.0700, :exercise, "Swiftwater refresher, Mamquam River"},
      {49.7016, -123.1580, :event, "Team meeting"}
    ]

    points
    |> Enum.map(fn {lat, lng, kind, title} -> %{lat: lat, lng: lng, kind: kind, tip: title} end)
    |> ActivityMap.build({720, 400}, padding: 48)
  end
end
