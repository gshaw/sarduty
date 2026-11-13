defmodule App.SilverBasin do
  @moduledoc """
  Silver Basin SAR (SBSAR), a made-up team (#963): Coast Range SAR's neighbour in WESARA
  (`App.CoastRange.organization/0`), so an organization has two teams' totals to show.
  Never a real person, team, or number: 250-555-01xx phones, and every date counts back
  from `now`.

  Small on purpose: five members, four incidents and two trainings in the past year, all
  with hours tags, so every member gets a tax letter and the organization's totals aren't
  zero. One qualification, Ground search and rescue. WESARA's incident fields, as D4H
  gives each team its organization's, filled in on every incident, since a published
  incident has every required one (#1003). No groups, equipment, chores, cards, or edge
  cases: those stay on Coast Range.

  Its names aren't plain English, as tax letters once crashed on: Ł is outside Latin-1,
  Trần Minh Châu has two marks on one letter and three names, and Siobhán
  O'Connor-Hale has an accent, an apostrophe, and a hyphen. No first or last name repeats
  one on Coast Range, so a sweep for one team's names never finds the other's.

  Pure: build/1 is rows in App.CoastRange.build/2's shape, for App.SampleRepo, a demo
  (App.DemoCast), and the dev teams (tools/dev-teams.exs).
  """

  alias App.CoastRange
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Tag
  alias App.Model.Team

  @timezone "America/Vancouver"
  @d4h_team_id 9_120_000

  # Name, ref id, phone, days on the team, and position. Jamie Sato is the team admin.
  @people [
    {"Jamie Sato", "201", "250-555-0101", 3000, "Team leader"},
    {"Kai Moreau", "202", "250-555-0102", 2400, "Search manager"},
    {"Łukasz Wójcik", "203", "250-555-0103", 1200, "Ground searcher"},
    {"Trần Minh Châu", "204", "250-555-0104", 900, "Ground searcher"},
    {"Siobhán O'Connor-Hale", "205", "250-555-0105", 600, "Ground searcher"}
  ]

  # Days ago, local hour, hours long, title, and its description.
  @incidents [
    {18, 10, 6, "Missing snowmobiler", "Found at the cabin and ridden out."},
    {74, 14, 4, "Overdue hikers", "Met on the trail at dusk."},
    {161, 8, 5, "Injured rider", "Carried out from the logging road."},
    {252, 18, 7, "Missing angler", "Found on the far bank of the lake."}
  ]

  # Each incident's answers to WESARA's fields: what SAR was tasked to do, the task type,
  # the subject's activity, the primary cause, and the alert. Only options Coast Range
  # uses, since WESARA's lists keep only those.
  @answers %{
    "Missing snowmobiler" =>
      {"Search - lost subject(s)", "002 - Land SAR", "Z - Unknown activity", "Lost/disoriented",
       "Concerned family member"},
    "Overdue hikers" =>
      {"Search - lost subject(s)", "002 - Land SAR", "L - Hiking", "Onset of darkness",
       "Concerned family member"},
    "Injured rider" =>
      {"Rescue - injury & medical emergency", "002 - Land SAR",
       "L - Biking (mountain or trail; pedal powered)", "Injury", "Telephone - cellular"},
    "Missing angler" =>
      {"Search - lost subject(s)", "003 - Inland water SAR", "Z - Unknown activity",
       "Lost/disoriented", "Concerned family member"}
  }

  @trainings [
    {39, 19, 3, "Ground search training"},
    {205, 9, 6, "Tracking day"}
  ]

  @tags ["Primary Hours", "Secondary Hours", "Training"]

  @doc "Silver Basin SAR's members, Jamie Sato first."
  def names, do: Enum.map(@people, &elem(&1, 0))

  @doc """
  Pure. Silver Basin SAR as of `now`: rows `{kind, key, struct, links}` in the order they
  insert, as App.CoastRange.build/2 gives Coast Range's.
  """
  def build(%DateTime{} = now) do
    now = DateTime.truncate(now, :second)
    today = Service.Period.today(now, @timezone)
    activities = activities(today)

    Enum.concat([
      [{:team, :silverbasin, team(now), []}],
      tags(),
      CoastRange.organization_fields(),
      Enum.map(@people, &member(&1, now)),
      qualification(today),
      Enum.map(activities, &{:activity, &1.d4h_activity_id, &1, []}),
      attendances(activities)
    ])
  end

  defp team(now) do
    %Team{
      name: "Silver Basin SAR",
      legal_name: "Silver Basin Search and Rescue Society",
      abbreviated_name: "SBSAR",
      subdomain: "silverbasin",
      d4h_team_id: @d4h_team_id,
      d4h_api_host: "api.ca.d4h.org",
      mailing_address: "200 Example Road",
      city: "Silver Basin BC",
      postal_code: "V0E 2A0",
      authorized_by_name: "Jamie Sato",
      authorized_by_title: "President",
      authorized_by_phone: "250-555-0101",
      authorized_by_email: CoastRange.email("Jamie Sato"),
      lat: 50.7,
      lng: -119.3,
      timezone: @timezone,
      member_logins: true,
      d4h_synced_at: usec(now),
      d4h_refreshed_at: usec(now)
    }
  end

  defp tags do
    for {title, i} <- Enum.with_index(@tags, 1) do
      {:tag, title,
       %Tag{d4h_tag_id: 9_720_000 + i, title: title, owner_type: "Team", owner_id: @d4h_team_id},
       []}
    end
  end

  # D4H's access levels: 0 Owner, 3 Member plus.
  defp member({name, ref_id, phone, days, position}, now) do
    member = %Member{
      d4h_member_id: 9_160_000 + String.to_integer(ref_id),
      ref_id: ref_id,
      name: name,
      email: CoastRange.email(name),
      phone: phone,
      address: "#{ref_id} Example Road",
      position: position,
      joined_at: now |> Service.Period.today(@timezone) |> Date.add(-days) |> day_start(),
      d4h_permission: if(name == "Jamie Sato", do: 0, else: 3),
      d4h_status: "OPERATIONAL",
      custom_values: %{}
    }

    {:member, name, member, []}
  end

  # Everyone holds it, from two months after joining, and it never expires.
  defp qualification(today) do
    qualification =
      {:qualification, 9_620_001,
       %Qualification{d4h_qualification_id: 9_620_001, title: "Ground search and rescue"}, []}

    awards =
      for {{name, _, _, days, _}, i} <- Enum.with_index(@people, 1) do
        row = %MemberQualificationAward{
          d4h_award_id: 962_000_100 + i,
          starts_at: today |> Date.add(60 - days) |> day_start()
        }

        {:award, {9_620_001, name}, row,
         member_id: {:member, name}, qualification_id: {:qualification, 9_620_001}}
      end

    [qualification | awards]
  end

  # In the order they started, so ref ids count up from 00800.
  defp activities(today) do
    today
    |> incidents()
    |> Enum.concat(trainings(today))
    |> Enum.sort_by(& &1.started_at, DateTime)
    |> Enum.with_index()
    |> Enum.map(fn {activity, i} ->
      %{
        activity
        | d4h_activity_id: 9_220_000 + i,
          ref_id: String.pad_leading("#{800 + i}", 5, "0"),
          hours_kind: "primary",
          is_published: true,
          custom_values: values(activity, i),
          address: "Silver Basin hall, 200 Example Road"
      }
    end)
  end

  defp incidents(today) do
    for {{days, hour, hours, title, description}, n} <- Enum.with_index(@incidents) do
      timed(
        %Activity{
          activity_kind: "incident",
          title: title,
          description: description,
          tracking_number: "SB-#{2104 - n}",
          tags: ["Primary Hours"]
        },
        today,
        days,
        hour,
        hours
      )
    end
  end

  defp values(%Activity{activity_kind: "incident", title: title} = activity, i) do
    {tasked, task_type, activity_type, cause, alert} = Map.fetch!(@answers, title)
    reported = activity.finished_at |> DateTime.to_date() |> Date.to_iso8601()

    CoastRange.organization_values([
      {"What was SAR tasked to do?", tasked},
      {"How many people were in the group that requested help?", "2"},
      {"How many people received assistance from SAR?", "2"},
      {"Response Type", "Response"},
      {"Agency", "Police"},
      {"Police Department", "RCMP - Royal Canadian Mounted Police"},
      {"Agency File #", "26-#{5120 - i * 41}"},
      {"Region", "South West"},
      {"Area", "Silver Basin"},
      {"Task Type", task_type},
      {"Task Leader's Name", if(rem(i, 2) == 0, do: "Jamie Sato", else: "Kai Moreau")},
      {"Date Report Completed", reported},
      {"Was RADeMS Discussed?", "YES"},
      {"Was a Level 2 SAR Manager Activated for this Incident?", "No"},
      {"SAR Severity",
       "Category 3 - Assistance required, subject not in grave or Imminent danger or not in distress"},
      {"Activity", activity_type},
      {"Primary Cause", cause},
      {"Was weather a factor in response?", "NO"},
      {"Alert Type", alert},
      {"Mutual Aid Requested?", "NO"}
    ])
  end

  defp values(_training, _i), do: %{}

  defp trainings(today) do
    for {days, hour, hours, title} <- @trainings do
      timed(
        %Activity{
          activity_kind: "exercise",
          title: title,
          description: "#{title} at the hall.",
          tags: ["Primary Hours", "Training"]
        },
        today,
        days,
        hour,
        hours
      )
    end
  end

  defp timed(activity, today, days, hour, hours) do
    start =
      today
      |> Date.add(-days)
      |> DateTime.new!(Time.new!(hour, 0, 0), @timezone)
      |> DateTime.shift_zone!("Etc/UTC")

    %{activity | started_at: start, finished_at: DateTime.add(start, hours, :hour)}
  end

  # Everyone attends the trainings; each member misses one incident, so totals differ.
  defp attendances(activities) do
    for {activity, a} <- Enum.with_index(activities),
        {{name, _, _, _, _}, i} <- Enum.with_index(@people),
        activity.activity_kind != "incident" or rem(a + i, 5) != 0,
        do: attendance(activity, name, 9_320_000 + a * 100 + i)
  end

  defp attendance(activity, name, d4h_attendance_id) do
    row = %Attendance{
      d4h_attendance_id: d4h_attendance_id,
      status: "attending",
      started_at: activity.started_at,
      finished_at: activity.finished_at,
      duration_in_minutes: DateTime.diff(activity.finished_at, activity.started_at, :minute)
    }

    {:attendance, {activity.d4h_activity_id, name}, row,
     member_id: {:member, name}, activity_id: {:activity, activity.d4h_activity_id}}
  end

  # A day D4H keeps without a time, as the copy stores it (docs/d4h-sync.md).
  defp day_start(date), do: Service.Convert.day_start(date, @timezone)
  defp usec(datetime), do: %{datetime | microsecond: {0, 6}}
end
