defmodule Web.StyleGuideHTML.SampleData do
  @moduledoc false

  alias Web.Components.ActivityMap

  # cspell:ignore Tremblay exsss
  # Made-up rows for the style guide, shaped like the app's pages.

  def letters do
    [
      %{
        id: 101,
        name: "Avery Chen",
        email: "avery@example.com",
        primary: "212h 30m",
        secondary: "18h 00m",
        total: "230h 30m",
        letter: "TCL-2025-014"
      },
      %{
        id: 117,
        name: "Blake Morrison",
        email: "blake@example.com",
        primary: "198h 15m",
        secondary: "4h 45m",
        total: "203h 00m",
        letter: nil
      },
      %{
        id: 123,
        name: "Casey Dhillon",
        email: "casey@example.com",
        primary: "156h 00m",
        secondary: "62h 30m",
        total: "218h 30m",
        letter: "TCL-2025-015"
      },
      %{
        id: 131,
        name: "Devon Okafor",
        email: "devon@example.com",
        primary: "88h 45m",
        secondary: "12h 15m",
        total: "101h 00m",
        letter: nil
      },
      %{
        id: 152,
        name: "Finley Tremblay",
        email: "finley@example.com",
        primary: "41h 00m",
        secondary: "9h 30m",
        total: "50h 30m",
        letter: nil
      }
    ]
  end

  # Page 2 of a long activity list, for the pagination example.
  def sample_page do
    %App.Page{entries: [], page_number: 2, page_size: 50, total_entries: 1912, total_pages: 39}
  end

  def sample_user, do: %App.Accounts.User{id: 0, email: "avery@example.com", is_admin: false}

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

  def recommendations do
    [
      %{op: :add, name: "Avery Chen", email: "avery@example.com", phone: "604-555-0101"},
      %{op: :add, name: "Casey Dhillon", email: "casey@example.com", phone: "604-555-0123"},
      %{op: :remove, name: "Devon Okafor", email: "devon@example.com", phone: "604-555-0131"},
      %{op: :not_invited, name: "Jordan Park", email: "jordan@example.com", phone: "604-555-0177"}
    ]
  end

  def clauses do
    [
      %{name: "First Aid", qualifications: ["OFA Level 1", "Wilderness First Aid", "EMR"]},
      %{name: "Ground Search", qualifications: ["GSAR Member", "Missing: Team Leader 2019"]},
      %{name: "", qualifications: []}
    ]
  end

  def preview do
    %{
      to_remove: [%{name: "Devon Okafor", reason: "No First Aid qualification"}],
      to_add: [%{name: "Avery Chen", reason: "Holds OFA Level 1 and GSAR Member"}],
      expiring: [
        %{name: "Casey Dhillon", reason: "Wilderness First Aid expires Nov 12", days: 12}
      ]
    }
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
