defmodule Web.StyleGuideHTML.SampleData do
  @moduledoc false

  alias App.Model.CustomField
  alias App.Model.Team
  alias App.ViewData.Milestones
  alias Service.Format
  alias Web.Components.ActivityMap

  # cspell:ignore Tremblay exsss
  # Made-up rows for the style guide, shaped like the app's pages.

  @doc """
  An incident's custom fields (#681), as the activity page shows them to a team admin:
  two with values and a required one left empty.
  """
  def custom_field_rows do
    field = fn id, title, type, options ->
      %CustomField{
        d4h_custom_field_id: id,
        title: title,
        field_type: type,
        required: true,
        options: options
      }
    end

    fields = [
      field.(1, "Primary Cause", "single_choice", [%{"id" => 10, "label" => "Lost"}]),
      field.(2, "Agency File #", "text", []),
      field.(3, "Was weather a factor in response?", "single_choice", [])
    ]

    CustomField.rows(fields, %{"1" => [10], "2" => "2026-123456"}, "America/Vancouver",
      missing: true
    )
  end

  @doc """
  An upload like the certificate form's, for the file drop: `:empty`, `:chosen` with a
  PDF, or `:too_large` with one refused. The guide has no LiveView, so it is built on a
  bare socket.
  """
  def sample_upload(state) do
    upload =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.LiveView.allow_upload(:certificate,
        accept: ~w(image/* application/pdf),
        max_entries: 1,
        max_file_size: Service.CertificateFile.max_bytes()
      )
      |> then(& &1.assigns.uploads.certificate)

    entry = %Phoenix.LiveView.UploadEntry{
      ref: "0",
      upload_ref: upload.ref,
      upload_config: :certificate,
      client_name: "first-aid.pdf",
      client_size: 245_000,
      client_type: "application/pdf",
      valid?: true
    }

    case state do
      :empty ->
        upload

      :chosen ->
        %{upload | entries: [entry]}

      :too_large ->
        %{
          upload
          | entries: [%{entry | client_size: 14_200_000, valid?: false}],
            errors: [{"0", :too_large}]
        }
    end
  end

  def letters do
    Enum.map(
      [
        {"Avery Chen", "avery@example.com", {212, 30}, {18, 0}, "TCL-2025-014"},
        {"Blake Morrison", "blake@example.com", {198, 15}, {4, 45}, nil},
        {"Casey Dhillon", "casey@example.com", {156, 0}, {62, 30}, "TCL-2025-015"},
        {"Devon Okafor", "devon@example.com", {88, 45}, {12, 15}, nil},
        {"Finley Tremblay", "finley@example.com", {41, 0}, {9, 30}, nil}
      ],
      &letter_row/1
    )
  end

  # Hours as `{hours, minutes}`, shown the way the letters page shows them.
  defp letter_row({name, email, primary, secondary, letter}) do
    primary = minutes(primary)
    secondary = minutes(secondary)

    %{
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

  # Who sees which switcher, for the top bar's examples: `{id, title, bar assigns}`.
  def sample_switchers do
    avery = sample_user()
    admin = %{avery | is_admin: true}
    squamish = sample_team()
    [_member, pemberton_member] = sample_member_logins()
    pemberton = pemberton_member.team

    on_squamish = %{
      current_team: squamish,
      current_member: sample_member(),
      team_admin?: true,
      managed_teams: [squamish],
      current_path: "/teams/squamish"
    }

    [
      {"one-team", "On one team",
       Map.merge(on_squamish, %{current_user: avery, member_logins: [sample_member()]})},
      {"teams", "On two teams",
       Map.merge(on_squamish, %{current_user: avery, member_logins: sample_member_logins()})},
      {"admin-one-team", "A SAR Duty admin on one team",
       Map.merge(on_squamish, %{current_user: admin, member_logins: [sample_member()]})},
      {"admin-teams", "A SAR Duty admin on two teams",
       Map.merge(on_squamish, %{current_user: admin, member_logins: sample_member_logins()})},
      {"admin-area", "A SAR Duty admin in SAR Duty admin",
       %{
         current_user: admin,
         current_team: squamish,
         managed_teams: [squamish],
         member_logins: sample_member_logins(),
         current_path: "/admin"
       }},
      {"admin-other-team", "A SAR Duty admin on a team that isn't theirs",
       %{
         current_user: admin,
         current_team: pemberton,
         team_admin?: true,
         current_path: "/teams/pemberton"
       }}
    ]
  end

  # Squamish's space on its activities, for a team admin who is a member, with 2
  # certificates waiting.
  def sample_nav_area,
    do:
      Web.Navigation.area(
        "/teams/squamish/activities",
        %{sample_team() | member_logins: true, certificates_enabled: true}
      )

  def sample_nav_sections,
    do:
      Web.Navigation.sections(sample_nav_area(), "/teams/squamish/activities",
        team_admin?: true,
        member?: true,
        certificates: 2
      )

  # Search results for "rope" on Squamish, as Web.Search.run/3 returns them, best first.
  def sample_search_groups do
    team = "/teams/squamish"

    for group <- [
          %{
            kind: :activity,
            more?: true,
            hits: [
              %{
                id: 2,
                title: "Rope rescue, Murrin Park",
                activity_kind: "exercise",
                ref_id: "25-0409",
                started_at: ~U[2025-09-24 16:00:00Z],
                path: "#{team}/activities/2"
              },
              %{
                id: 7,
                title: "Technical rope rescue, Cheakamus Canyon",
                activity_kind: "incident",
                ref_id: "25-0388",
                started_at: ~U[2025-09-08 19:00:00Z],
                path: "#{team}/activities/7"
              }
            ]
          },
          %{
            kind: :qualification,
            more?: false,
            hits: [
              %{id: 1, title: "Rope Rescue Team Member", path: "#{team}/qualifications/1"},
              %{id: 2, title: "Rope Rescue Team Leader", path: "#{team}/qualifications/2"}
            ]
          },
          %{
            kind: :member,
            more?: false,
            hits: [
              %{
                id: 3,
                title: "Robin Ropes",
                position: "Rope team lead",
                standing: {:away, ~D[2025-11-03]},
                path: "#{team}/members/3"
              }
            ]
          },
          %{
            kind: :equipment,
            more?: false,
            hits: [
              %{
                id: 4,
                title: "Rope rescue kit 2",
                barcode: "SQ-0142",
                location_title: "Hall",
                in_service?: true,
                status: "operational",
                path: "#{team}/equipment/4"
              }
            ]
          }
        ],
        do: %{group | hits: Enum.map(group.hits, &Map.put(&1, :kind, group.kind))}
  end

  # Recent picks on Squamish, newest first, as Web.Search.recent/3 returns them.
  def sample_search_recent do
    team = "/teams/squamish"

    [
      %{
        kind: :recent,
        more?: false,
        hits: [
          %{
            kind: :member,
            id: 3,
            title: "Robin Ropes",
            position: "Rope team lead",
            standing: :active,
            path: "#{team}/members/3"
          },
          %{
            kind: :activity,
            id: 2,
            title: "Rope rescue, Murrin Park",
            activity_kind: "exercise",
            ref_id: "25-0409",
            started_at: ~U[2025-09-24 16:00:00Z],
            path: "#{team}/activities/2"
          },
          %{
            kind: :page,
            id: "tax-credit-letters",
            title: "Tax credit letters",
            path: "#{team}/tax-credit-letters"
          }
        ]
      }
    ]
  end

  def sample_team do
    %App.Model.Team{
      id: 0,
      name: "Squamish SAR",
      subdomain: "squamish",
      timezone: "America/Vancouver"
    }
  end

  # An exercise 3 hours after panel_now/0, for the activity panel and reply examples.
  def panel_activity do
    %App.Model.Activity{
      id: 2,
      title: "Rope rescue, Murrin Park",
      activity_kind: "exercise",
      address: "Murrin Park",
      started_at: ~U[2025-09-30 02:00:00Z],
      finished_at: ~U[2025-09-30 05:00:00Z]
    }
  end

  def panel_now, do: ~U[2025-09-29 23:00:00Z]

  def panel_counts, do: %{attending: 6, absent: 2, requested: 5}

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
  # Ends relative to now, so the Expires cell shows its three states.
  def qualification_rows do
    now = DateTime.utc_now()

    [
      %{
        id: 1,
        title: "Standard First Aid",
        ends_at: DateTime.add(now, 45, :day),
        expired?: false
      },
      %{
        id: 2,
        title: "Rope Rescue Operations",
        ends_at: DateTime.add(now, 400, :day),
        expired?: false
      },
      %{id: 3, title: "ICS 100", ends_at: nil, expired?: false},
      %{
        id: 4,
        title: "Swiftwater Awareness",
        ends_at: DateTime.add(now, -400, :day),
        expired?: true
      }
    ]
  end

  # Members by standing, for the table's row groups.
  # The standard columns (#740) for /styles/table, in Web.Components.Columns' order.
  def standard_columns do
    [
      {"Member", "member_cell", "Left",
       "Every table that lists the members of something: an activity, a group, a qualification, chores, tax letters. The standing badge follows the name."},
      {"Activity", "activity_cell", "Left",
       "Every table of activities. Pass kind={false} when the table has a Kind column."},
      {"Item", "item_cell", "Left",
       "Every table of equipment. The status badge shows unless the item is operational."},
      {"Qualification", "qualification_cell", "Left", "Every table of qualifications."},
      {"Group", "group_cell", "Left", "Every table of groups."},
      {"Date", "date_cell", "Left",
       "A day: when an activity started, a chore, a milestone. Also Joined, Retired, Start, and Sent. Pass activity={…} for an activity's start, so a chore activity reads as its month, \"Oct 2026\". The Activities list alone adds times, for its start and end under the date, with +1 when it ends the next day."},
      {"Expires", "expires_cell", "Left",
       "When a qualification, certificate, or item runs out. The badge counts the days left within 60."},
      {"Hours", "hours_cell", "Right",
       "Time spent: on an activity, a chore, or a year's tax credit hours."},
      {"Last attended", "last_attended_cell", "Left",
       "How long since a member last attended. The date shows on hover."}
    ]
    |> Enum.map(fn {label, cell, align, use} ->
      %{id: cell, label: label, cell: cell, align: align, use: use}
    end)
  end

  def sample_item,
    do: %App.Model.EquipmentItem{id: 1, title: "Rope kit 2", status: "unserviceable"}

  # The Member column's standings, one row each, for /styles/table.
  def member_column_rows do
    away = %App.Model.MemberAwayPeriod{ends_on: ~D[2026-03-01], reason: "Parental leave"}

    [
      %{id: 1, name: "Avery Chen", role: "Team leader", standing: :active},
      %{id: 2, name: "Casey Dhillon", role: "Member", standing: {:away, away}},
      %{id: 3, name: "Jordan Price", role: "Member", standing: :retiring},
      %{id: 4, name: "Kiosk sign-in", role: nil, standing: :not_a_person},
      %{id: 5, name: "Sam Okafor", role: "Member", standing: :retired}
    ]
  end

  def member_groups do
    now = DateTime.utc_now()

    [
      %{
        id: "active",
        title: "Active",
        rows: [
          %{id: 1, name: "Casey Dhillon", last_attended: DateTime.add(now, -15, :day)},
          %{id: 2, name: "Morgan Lee", last_attended: DateTime.add(now, -27, :day)}
        ]
      },
      %{
        id: "away",
        title: "Away",
        rows: [%{id: 3, name: "Sam Okafor", last_attended: DateTime.add(now, -130, :day)}]
      },
      %{
        id: "retired",
        title: "Retired",
        muted: true,
        rows: [%{id: 4, name: "Jordan Price", last_attended: nil}]
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
      {"Endorsements", [{"First Aid", "endorsement:1"}, {"Swiftwater 1", "endorsement:2"}]}
    ]

  # Team settings' Tax credit letters tab after a failed save: the app's own changeset,
  # with a phone number too long and an email that isn't one.
  def settings_form do
    team = %{sample_team() | mailing_address: "PO Box 123\nSquamish BC V8B 0A1"}

    params = %{
      "authorized_by_name" => "Avery Chen",
      "authorized_by_phone" => "604 555 0100, or 604 555 0101 after 6 pm",
      "authorized_by_email" => "avery at example"
    }

    team
    |> Team.build_letters_changeset(params)
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

  @doc "A sample address box's form, with these values."
  def place_form(values \\ %{}) do
    %{"place" => "", "coordinate" => ""}
    |> Map.merge(values)
    |> Phoenix.Component.to_form(as: "demo")
  end

  @doc "The team's places a sample address box lists before typing."
  def sample_past_places do
    [
      %{
        text: "17543 20 Ave, Surrey",
        name: "Base",
        coordinate: "49.03879,-122.73734",
        count: 57,
        last_at: ~U[2026-10-20 02:00:00Z]
      },
      %{
        text: "Campbell Valley Regional Park, Langley",
        name: nil,
        coordinate: "49.01732,-122.65634",
        count: 9,
        last_at: ~U[2026-09-14 16:00:00Z]
      }
    ]
  end

  @doc "A place Mapbox's Search Box suggests."
  def sample_mapbox_places,
    do: [%{id: "sample", name: "Base Camp Coffee", detail: "Langley, British Columbia"}]
end
