defmodule App.CoastRange do
  @moduledoc """
  Coast Range SAR (CRSAR), the made-up team (#816): the cast every mockup draws
  (docs/mockups.md), and the team an agent's report runs on (App.SampleRepo). Never a
  real person, team, or number: names, ref ids, and 604-555-01xx phone numbers never
  change, and every date counts back from `now`.

  It fills every field a report reads: a year of activities of each kind with tags,
  hours tags, tracking numbers, drafts, and a missing required field; attendance
  attended, absent, and signed up for the coming week; groups, with a Retiring one;
  qualifications and awards, some expiring, and the endorsements ID cards list;
  equipment and its use; chores; an away member, a retired one, and one that isn't a
  person; and the sample ID cards the verify site's /samples page shows (#854).

  Pure: build/1 is rows, and App.Operation.SeedCoastRange inserts them.

  ## Who to use

  Each member stands for one case. A mockup or a test that needs the case picks that
  member, so the same person always means the same thing; App.CoastRangeTest keeps each
  line true. A case not listed gets a new member, never a second meaning for one here.

  - **Alex Chen**, team leader: the team admin. Logs in to every team admin page, and
    is who did it in history and change sets. Search manager, Rope team.
  - **Cameron Ruiz**, ground searcher: the member. Logs in to Your membership, replies,
    and the ID card. First aid expires in 15 days; holds Radio 3; a chore waiting.
  - **Avery Chen**, search manager: in Team leaders beside Alex, and the same last name,
    for sorting and search. First aid expires in 25 days.
  - **Blake Morrison**, rope rescue technician: a current member holding team equipment
    (Rope kit B). Rope rescue expires in 20 days.
  - **Casey Dhillon**, swiftwater technician: an ordinary member, nothing to flag. Use
    for a row that should show no badge or warning.
  - **Dana Kowal**, ground searcher: Away, from 10 days ago to 20 days on.
  - **Drew Patel**, rope rescue technician: an award that has expired (first aid, 10
    days ago).
  - **Eli Haddad**, ground searcher: details missing, with no address.
  - **Harper Nguyen**, team leader: the third in Team leaders, for a list of several.
  - **Jordan Lee**, ground searcher: a newer member, a year on. A chore waiting.
  - **Noor Aziz**, swiftwater technician: chores accepted every month, with Priya.
  - **Priya Nair**, first aid lead: chores accepted every month, and an expired
    swiftwater award.
  - **Quinn Laval**, ground searcher: No access in D4H, so no login.
  - **Riley Okafor**, ground searcher: new, joined 40 days ago. In no group and holds no
    award yet.
  - **Sam Rivera**, ground searcher: Retiring. Hasn't attended in 120 days; holds Radio 2,
    so equipment with a retiring member.
  - **Robin Tse**: Retired, 120 days ago.
  - **Duty pager**: not a person. No email, never attends.

  Activities, by title: **Missing hiker** is the newest incident, a draft missing its
  agency file number; **Trail safety booth** is an event in 4 days; the coming Tuesday's
  training has sign-ups, can't-make-its, and no replies; **Night search exercise** is in
  12 days; **Evidence search** has no hours tag and **Missing hunter** has both.
  """

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreCategoryTag
  alias App.Model.ChoreEvent
  alias App.Model.CustomField
  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCard
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Tag
  alias App.Model.Team

  # cspell:ignore CRSAR Kowal Noor Priya Okafor

  @timezone "America/Vancouver"
  @d4h_team_id 9_100_000

  # Name, ref id, phone, days on the team, position, and what sets them apart. Alex Chen
  # is the team admin and Cameron Ruiz the member mockups log in as.
  @people [
    {"Alex Chen", "112", "604-555-0112", 4400, "Team leader", [:owner]},
    {"Avery Chen", "130", "604-555-0120", 3300, "Search manager", []},
    {"Blake Morrison", "131", "604-555-0121", 2950, "Rope rescue technician", []},
    {"Cameron Ruiz", "132", "604-555-0122", 1100, "Ground searcher", []},
    {"Casey Dhillon", "133", "604-555-0123", 2200, "Swiftwater technician", []},
    {"Dana Kowal", "134", "604-555-0124", 1850, "Ground searcher", [:away]},
    {"Drew Patel", "135", "604-555-0125", 1500, "Rope rescue technician", []},
    {"Eli Haddad", "136", "604-555-0126", 800, "Ground searcher", [:no_address]},
    {"Harper Nguyen", "137", "604-555-0127", 2600, "Team leader", []},
    {"Jordan Lee", "138", "604-555-0128", 420, "Ground searcher", []},
    {"Noor Aziz", "139", "604-555-0129", 1450, "Swiftwater technician", []},
    {"Priya Nair", "140", "604-555-0130", 2250, "First aid lead", []},
    {"Quinn Laval", "141", "604-555-0131", 1050, "Ground searcher", [:no_access]},
    {"Riley Okafor", "142", "604-555-0132", 40, "Ground searcher", []},
    {"Sam Rivera", "143", "604-555-0133", 3700, "Ground searcher", [:retiring]},
    {"Robin Tse", "144", "604-555-0134", 3500, "Ground searcher", [:retired]},
    {"Duty pager", "145", "604-555-0135", 2000, nil, [:not_a_person]}
  ]

  # Days ago, local hour, hours long, title, and its description.
  @incidents [
    {3, 14, 5, "Missing hiker", "Found on the ridge trail and walked out."},
    {11, 9, 7, "Overdue kayakers", "Two kayakers found on the far shore, cold but well."},
    {19, 22, 4, "Injured mountain biker", "Carried out to the trailhead by stretcher."},
    {33, 16, 6, "Lost child, day-use area", "Found asleep under a picnic table."},
    {47, 7, 9, "Missing hunter", "Found at first light and flown out."},
    {62, 18, 3, "Stranded skiers", "Guided down from the bowl before dark."},
    {80, 13, 5, "Fallen climber", "Rope rescue from a ledge, then a carry-out."},
    {101, 20, 8, "Missing person, river", "Searched both banks; handed over to police."},
    {127, 11, 4, "Evidence search", "Line search of a field for police."},
    {150, 15, 6, "Overdue snowshoers", "Met on the trail coming out."},
    {181, 10, 3, "Vehicle over the bank", "Hauled the driver up the bank by rope."},
    {220, 17, 5, "Injured hiker, carry-out", "Ankle injury, carried 3 km."},
    {268, 8, 10, "Missing berry picker", "Found by a dog team after a night out."},
    {320, 19, 4, "Swiftwater rescue", "Swimmer pulled from the river at the falls."}
  ]

  # Days from today (before it when negative), local hour, hours long, and title.
  @events [
    {-24, 10, 4, "School safety talk"},
    {-75, 9, 6, "Community fair booth"},
    {-140, 11, 5, "Fundraising barbecue"},
    {-200, 19, 2, "Annual general meeting"},
    {-290, 9, 3, "Gear check day"},
    {4, 10, 4, "Trail safety booth"}
  ]

  @trainings [
    {"Rope rescue training", ["Rope"]},
    {"Navigation night", []},
    {"Swiftwater training", ["Swiftwater"]},
    {"First aid scenarios", []},
    {"Search tactics", []},
    {"Radio and mapping", []}
  ]

  @tags ["Primary Hours", "Secondary Hours", "Training", "Rope", "Swiftwater"] ++
          ["Public education", "Chores"]

  @groups [
    {9_500_001, "Callout", :all},
    {9_500_002, "Rope team",
     ["Alex Chen", "Avery Chen", "Blake Morrison", "Drew Patel", "Harper Nguyen"]},
    {9_500_003, "Swiftwater team",
     ["Casey Dhillon", "Eli Haddad", "Jordan Lee", "Noor Aziz", "Priya Nair"]},
    {9_500_004, "Team leaders", ["Alex Chen", "Avery Chen", "Harper Nguyen"]},
    {9_500_005, "Retiring", ["Sam Rivera"]}
  ]

  # D4H id, title, months an award lasts, and who holds it with the days from today it
  # expires: some soon, one gone.
  @qualifications [
    {9_600_001, "Ground search and rescue", nil, :all},
    {9_600_002, "First aid", 36,
     [
       {"Alex Chen", 400},
       {"Avery Chen", 25},
       {"Blake Morrison", 700},
       {"Cameron Ruiz", 15},
       {"Casey Dhillon", 300},
       {"Dana Kowal", 900},
       {"Drew Patel", -10},
       {"Eli Haddad", 500},
       {"Harper Nguyen", 200},
       {"Jordan Lee", 60},
       {"Noor Aziz", 800},
       {"Priya Nair", 1000},
       {"Quinn Laval", 45},
       {"Sam Rivera", 600},
       {"Robin Tse", -200}
     ]},
    {9_600_003, "Rope rescue technician", 36,
     [
       {"Alex Chen", 500},
       {"Avery Chen", 120},
       {"Blake Morrison", 20},
       {"Drew Patel", 650},
       {"Harper Nguyen", 330}
     ]},
    {9_600_004, "Swiftwater rescue technician", 36,
     [
       {"Casey Dhillon", 250},
       {"Eli Haddad", 40},
       {"Jordan Lee", 900},
       {"Noor Aziz", 410},
       {"Priya Nair", -30}
     ]},
    {9_600_005, "Search manager", 60, [{"Alex Chen", 700}, {"Avery Chen", 1300}]}
  ]

  # Title, type, kind, status, and who holds it.
  @equipment [
    {9_800_001, "Truck 1", "vehicle", "Truck", "operational", nil},
    {9_800_002, "Radio 1", "equipment", "Radio", "operational", nil},
    {9_800_003, "Radio 2", "equipment", "Radio", "operational", "Sam Rivera"},
    {9_800_004, "Radio 3", "equipment", "Radio", "operational", "Cameron Ruiz"},
    {9_800_005, "Radio 4", "equipment", "Radio", "unserviceable", nil},
    {9_800_006, "Rope kit A", "equipment", "Rope kit", "operational", nil},
    {9_800_007, "Rope kit B", "equipment", "Rope kit", "operational", "Blake Morrison"},
    {9_800_008, "AED", "equipment", "AED", "operational", nil},
    {9_800_009, "Throw bag", "supply", "Throw bag", "operational", nil},
    {9_800_010, "Old GPS", "equipment", "GPS", "retired", nil},
    {9_800_011, "Headlamp 3", "equipment", "Headlamp", "lost", nil}
  ]

  # Each month's accepted chores: who, the day, minutes, and what.
  @chores [
    {"Priya Nair", 5, 90, "Checked the first aid packs."},
    {"Noor Aziz", 12, 120, "Washed and fuelled the truck."},
    {"Cameron Ruiz", 19, 60, "Swept the hall."},
    {"Alex Chen", 26, 180, "Sorted the rope cache."}
  ]

  @agency 9_400_001
  @file_number 9_400_002
  @call_sign 9_400_003
  @serviced 9_400_004
  @task_type 9_400_005
  @people_helped 9_400_006
  @team_notes 9_400_007
  @exercise_leader 9_400_008
  @event_leader 9_400_009
  @areas 9_400_010

  # Each incident's task type, people helped, and a team admin's notes (RESTRICTED).
  @task_types ["Search", "Rescue", "Evidence search"]
  @rescues [
    "Injured mountain biker",
    "Stranded skiers",
    "Fallen climber",
    "Vehicle over the bank",
    "Injured hiker, carry-out",
    "Swiftwater rescue"
  ]
  @helped %{
    "Overdue kayakers" => 2,
    "Stranded skiers" => 3,
    "Overdue snowshoers" => 2,
    "Evidence search" => 0
  }
  @notes %{
    "Missing hunter" => "Debrief: radios had a dead spot at the north gate.",
    "Fallen climber" => "Debrief: the second rope kit was still at the hall."
  }
  @areas_options ["Fundraising", "Training", "Public education", "Vehicle care"]
  @member_areas %{
    "Cameron Ruiz" => ["Fundraising", "Public education"],
    "Priya Nair" => ["Training", "Vehicle care"],
    "Noor Aziz" => ["Vehicle care"],
    "Casey Dhillon" => ["Fundraising"]
  }
  @leaders ["Alex Chen", "Harper Nguyen", "Avery Chen"]

  @doc "Coast Range SAR's time zone."
  def timezone, do: @timezone

  @doc "Every member's name, Alex Chen first."
  def names, do: Enum.map(@people, &elem(&1, 0))

  @doc """
  Pure. Coast Range SAR as of `now`: rows `{kind, key, struct, links}` in the order they
  insert. `links` names each foreign key's row as `{field, {kind, key}}`; every row but
  the team's also gets the team's id.
  """
  def build(%DateTime{} = now) do
    now = DateTime.truncate(now, :second)
    today = Service.Period.today(now, @timezone)
    activities = activities(now, today)

    Enum.concat([
      [{:team, :coastrange, team(now), []}],
      tags(),
      custom_fields(),
      members(now),
      groups(),
      qualifications(today),
      endorsements(),
      member_cards(now),
      Enum.map(activities, &{:activity, &1.d4h_activity_id, &1, []}),
      attendances(activities, now, today),
      equipment(today),
      equipment_usages(activities),
      away_periods(today),
      chores(activities, today)
    ])
  end

  defp team(now) do
    %Team{
      name: "Coast Range SAR",
      legal_name: "Coast Range Search and Rescue Society",
      abbreviated_name: "CRSAR",
      subdomain: "coastrange",
      d4h_team_id: @d4h_team_id,
      d4h_api_host: "api.ca.d4h.org",
      mailing_address: "123 Main St",
      lat: 49.2,
      lng: -123.1,
      timezone: @timezone,
      member_logins: true,
      chores_enabled: true,
      certificates_enabled: true,
      id_cards_enabled: true,
      whiteboard_enabled: true,
      retiring_d4h_group_id: 9_500_005,
      d4h_synced_at: usec(now),
      d4h_refreshed_at: usec(now)
    }
  end

  defp tags do
    for {title, i} <- Enum.with_index(@tags, 1) do
      {:tag, title,
       %Tag{d4h_tag_id: 9_700_000 + i, title: title, owner_type: "Team", owner_id: @d4h_team_id},
       []}
    end
  end

  defp custom_fields do
    agency_options =
      for {label, i} <- Enum.with_index(["Police", "Ambulance", "Fire"]) do
        %{"id" => agency_option(label), "label" => label, "ordering" => i, "archived" => false}
      end

    [
      custom_field(@agency, "incident", "Requesting agency", "single_choice",
        required: true,
        options: agency_options
      ),
      custom_field(@file_number, "incident", "Agency file number", "text", required: true),
      custom_field(@call_sign, "member", "Radio call sign", "text",
        member_privacy: "viewable",
        copy_values: true
      ),
      custom_field(@serviced, "equipment", "Last serviced", "date", []),
      custom_field(@task_type, "incident", "Task type", "single_choice",
        required: true,
        options: options(@task_types, &task_option/1)
      ),
      custom_field(@people_helped, "incident", "People helped", "number", []),
      custom_field(@team_notes, "incident", "Team notes", "text_area", restricted: true),
      # The same title on two kinds: a report reads it as one field.
      custom_field(@exercise_leader, "exercise", "Event leader", "text", []),
      custom_field(@event_leader, "event", "Event leader", "text", []),
      custom_field(@areas, "member", "Areas of assistance", "multiple_choice",
        member_privacy: "editable",
        copy_values: true,
        options: options(@areas_options, &area_option/1)
      )
    ]
  end

  defp options(labels, id) do
    for {label, i} <- Enum.with_index(labels) do
      %{"id" => id.(label), "label" => label, "ordering" => i, "archived" => false}
    end
  end

  defp task_option(label), do: 9_400_201 + Enum.find_index(@task_types, &(&1 == label))
  defp area_option(label), do: 9_400_301 + Enum.find_index(@areas_options, &(&1 == label))

  defp custom_field(id, target, title, type, attrs) do
    field =
      struct!(
        %CustomField{
          d4h_custom_field_id: id,
          target: target,
          title: title,
          field_type: type,
          owner_type: "Team",
          owner_id: @d4h_team_id
        },
        attrs
      )

    {:custom_field, id, field, []}
  end

  defp agency_option("Police"), do: 9_400_101
  defp agency_option("Ambulance"), do: 9_400_102
  defp agency_option("Fire"), do: 9_400_103

  defp members(now), do: Enum.map(@people, &member(&1, now))

  defp member({name, ref_id, phone, days, position, marks}, now) do
    person? = :not_a_person not in marks
    retired? = :retired in marks

    member = %Member{
      d4h_member_id: 9_110_000 + String.to_integer(ref_id),
      ref_id: ref_id,
      name: name,
      email: if(person?, do: email(name)),
      phone: phone,
      address: if(person? and :no_address not in marks, do: "#{ref_id} Example Road"),
      position: position,
      joined_at: DateTime.add(now, -days, :day),
      d4h_permission: permission(marks),
      d4h_status: if(retired?, do: "RETIRED", else: "OPERATIONAL"),
      left_at: if(retired?, do: left_at(now)),
      not_a_person: not person?,
      custom_values: member_values(name, ref_id)
    }

    {:member, name, member, []}
  end

  defp email(name), do: "#{name |> String.downcase() |> String.replace(" ", ".")}@example.com"

  defp left_at(now), do: DateTime.add(now, -120, :day)

  defp member_values(name, ref_id) do
    values = %{"#{@call_sign}" => "CR #{ref_id}"}

    case @member_areas[name] do
      nil -> values
      areas -> Map.put(values, "#{@areas}", Enum.map(areas, &area_option/1))
    end
  end

  # D4H's access levels: 0 Owner, 3 Member plus, 4 No access.
  defp permission(marks) do
    cond do
      :owner in marks -> 0
      :no_access in marks -> 4
      true -> 3
    end
  end

  defp person(name), do: Enum.find(@people, &(elem(&1, 0) == name))

  # On the team now and a person: everyone a group of all, or an award, holds.
  defp current_people,
    do:
      for(
        {name, _, _, _, _, marks} <- @people,
        :retired not in marks,
        :not_a_person not in marks,
        do: name
      )

  defp groups do
    for {d4h_id, title, names} <- @groups do
      names =
        if names == :all, do: current_people() -- ["Riley Okafor", "Sam Rivera"], else: names

      group = {:group, d4h_id, %Group{d4h_group_id: d4h_id, title: title}, []}

      members =
        for {name, i} <- Enum.with_index(names, 1) do
          row = %GroupMember{d4h_group_membership_id: d4h_id * 100 + i}

          {:group_member, {d4h_id, name}, row,
           group_id: {:group, d4h_id}, member_id: {:member, name}}
        end

      [group | members]
    end
    |> List.flatten()
  end

  defp qualifications(today) do
    for {d4h_id, title, months, holders} <- @qualifications do
      qualification =
        {:qualification, d4h_id,
         %Qualification{
           d4h_qualification_id: d4h_id,
           title: title,
           expires_months_default: months
         }, []}

      [qualification | awards(d4h_id, months, holders, today)]
    end
    |> List.flatten()
  end

  # Ground search and rescue never expires, and comes two months after joining.
  defp awards(d4h_id, nil, :all, today) do
    for {name, i} <- Enum.with_index(current_people() -- ["Riley Okafor"], 1) do
      {_, _, _, days, _, _} = person(name)
      award(d4h_id, name, i, Date.add(today, 60 - days), nil)
    end
  end

  defp awards(d4h_id, months, holders, today) do
    for {{name, expires_in}, i} <- Enum.with_index(holders, 1) do
      ends = Date.add(today, expires_in)
      award(d4h_id, name, i, Date.shift(ends, month: -months), ends)
    end
  end

  defp award(d4h_id, name, i, starts, ends) do
    row = %MemberQualificationAward{
      d4h_award_id: d4h_id * 100 + i,
      starts_at: noon(starts),
      ends_at: ends && noon(ends)
    }

    {:award, {d4h_id, name}, row,
     member_id: {:member, name}, qualification_id: {:qualification, d4h_id}}
  end

  # The endorsements ID cards list, each earned by one qualification.
  @endorsements [{"First aid", 9_600_002}, {"Ground search and rescue", 9_600_001}]

  defp endorsements do
    for {name, d4h_qualification_id} <- @endorsements do
      [
        {:endorsement, name, %Endorsement{name: name, on_card: true}, []},
        {:endorsement_qualification, name,
         %EndorsementQualification{d4h_qualification_id: d4h_qualification_id},
         endorsement_id: {:endorsement, name}}
      ]
    end
    |> List.flatten()
  end

  @doc """
  The sample ID cards (#854): what each shows on the verify site, its stored code, and
  whose it is. `SAMPNCRD` matches no card, for "No card has this code". Codes start with
  `SAMP`, which MemberCard.generate_code/0 never makes, and the verify site looks them up
  in App.SampleRepo only.
  """
  def sample_cards do
    [
      %{status: :active, code: "SAMPACTV", member: "Cameron Ruiz"},
      %{status: :inactive, code: "SAMPRTRD", member: "Robin Tse"},
      %{status: :revoked, code: "SAMPCNCD", member: "Cameron Ruiz"},
      %{status: :not_found, code: "SAMPNCRD", member: nil}
    ]
  end

  # The cancelled card is Cameron's last one, replaced a month ago, so it goes first.
  defp member_cards(now) do
    revoked_at = now |> DateTime.add(-30, :day) |> usec()

    for %{member: name} = sample <- Enum.sort_by(sample_cards(), &(&1.status != :revoked)),
        name != nil do
      card = %MemberCard{
        code: sample.code,
        serial_number: "coastrange-#{ref_id(name)}",
        revoked_at: if(sample.status == :revoked, do: revoked_at)
      }

      {:member_card, sample.code, card, member_id: {:member, name}}
    end
  end

  defp ref_id(name), do: name |> person() |> elem(1)

  # D4H's whole-day dates, at noon UTC so they read as the same day in Vancouver.
  defp noon(date), do: DateTime.new!(date, ~T[12:00:00], "Etc/UTC")

  defp local(date, hour),
    do: date |> DateTime.new!(Time.new!(hour, 0, 0), @timezone) |> DateTime.shift_zone!("Etc/UTC")

  # A year of weekly training to the coming Tuesday, the incidents, the events, a night
  # exercise in two weeks, and a chore activity for each of the last three months, in
  # the order they started: ref ids count up from 01400 in that order.
  defp activities(now, today) do
    [
      night_exercise(today)
      | training_places(trainings(today)) ++ incidents(today) ++ events(today)
    ]
    |> Enum.concat(chore_activities(today))
    |> Enum.sort_by(& &1.started_at, DateTime)
    |> Enum.with_index()
    |> Enum.map(fn {activity, i} ->
      %{
        activity
        | d4h_activity_id: 9_200_000 + i,
          ref_id: String.pad_leading("#{1400 + i}", 5, "0"),
          hours_kind: hours_kind(activity),
          # Two weeks gives a team admin time to fill in the fields and publish.
          is_published: DateTime.diff(now, activity.finished_at, :day) > 14
      }
    end)
  end

  defp trainings(today) do
    tuesday = next_tuesday(today)

    for week <- 0..51 do
      {title, tags} = Enum.at(@trainings, rem(week, length(@trainings)))
      start = tuesday |> Date.add(-7 * week) |> local(19)

      %Activity{
        activity_kind: "exercise",
        title: title,
        description: "Weekly training: #{String.downcase(title)}.",
        custom_values: exercise_values(week),
        started_at: start,
        finished_at: DateTime.add(start, 150, :minute),
        tags: ["Primary Hours", "Training" | tags],
        # The last four were sent from SAR Duty's door.
        attendance_sent_at: if(week in 1..4, do: start |> DateTime.add(3, :hour) |> usec())
      }
    end
  end

  # The first Tuesday from tomorrow on.
  defp next_tuesday(today) do
    tomorrow = Date.add(today, 1)
    Date.add(tomorrow, rem(2 - Date.day_of_week(tomorrow) + 7, 7))
  end

  defp exercise_values(week), do: %{"#{@exercise_leader}" => Enum.at(@leaders, rem(week, 3))}

  defp incidents(today) do
    for {{days, hour, hours, title, description}, n} <- Enum.with_index(@incidents) do
      start = today |> Date.add(-days) |> local(hour)

      %Activity{
        activity_kind: "incident",
        title: title,
        description: description,
        tracking_number: "CR-#{4113 - n}",
        started_at: start,
        finished_at: DateTime.add(start, hours, :hour),
        tags: incident_tags(title),
        custom_values: incident_values(title, days, n),
        coordinate: incident_place(n),
        address: "Cedar Creek forest road, spur #{rem(n * 4, 9) + 1}"
      }
    end
  end

  defp events(today) do
    for {days, hour, hours, title} <- @events do
      start = today |> Date.add(days) |> local(hour)

      %Activity{
        activity_kind: "event",
        title: title,
        description: "#{title} for the public.",
        custom_values: %{"#{@event_leader}" => "Priya Nair"},
        started_at: start,
        finished_at: DateTime.add(start, hours, :hour),
        tags: event_tags(title),
        coordinate: "49.25000,-123.10000",
        address: "Coast Range SAR hall, 100 Example Road",
        enough_at: 4
      }
    end
  end

  # made-up places, for reports and maps. Weekly training takes
  # turns between the two grounds.
  defp training_places(trainings) do
    grounds = [
      {"49.37000,-123.02000", "Cedar Creek training ground"},
      {"49.33000,-122.86000", "Hall training yard"}
    ]

    trainings
    |> Enum.with_index()
    |> Enum.map(fn {training, week} ->
      {coordinate, address} = Enum.at(grounds, rem(week, 2))
      %{training | coordinate: coordinate, address: address}
    end)
  end

  # spread over the mountains north of the base, the same every run.
  defp incident_place(n) do
    lat = 49.3 + rem(n * 37, 40) / 100
    lng = -123.35 + rem(n * 53, 90) / 100
    :io_lib.format("~.5f,~.5f", [lat, lng]) |> IO.iodata_to_binary()
  end

  defp event_tags("Annual general meeting"), do: ["Secondary Hours"]
  defp event_tags(_title), do: ["Secondary Hours", "Public education"]

  defp night_exercise(today) do
    start = today |> Date.add(12) |> local(18)

    %Activity{
      activity_kind: "exercise",
      title: "Night search exercise",
      description: "A mock search after dark, with a subject to find.",
      started_at: start,
      finished_at: DateTime.add(start, 5, :hour),
      tags: ["Primary Hours", "Training"],
      coordinate: "49.45000,-122.95000",
      address: "Cedar Creek forest road, km 12",
      enough_at: 8,
      full_at: 14
    }
  end

  defp hours_kind(%Activity{tags: tags}) do
    cond do
      "Primary Hours" in tags -> "primary"
      "Secondary Hours" in tags -> "secondary"
      true -> nil
    end
  end

  # The hours tags report finds one with none, and one with both.
  defp incident_tags("Evidence search"), do: []
  defp incident_tags("Missing hunter"), do: ["Primary Hours", "Secondary Hours"]
  defp incident_tags("Fallen climber"), do: ["Primary Hours", "Rope"]
  defp incident_tags("Vehicle over the bank"), do: ["Primary Hours", "Rope"]

  defp incident_tags(title) when title in ["Overdue kayakers", "Swiftwater rescue"],
    do: ["Primary Hours", "Swiftwater"]

  defp incident_tags("Missing person, river"), do: ["Primary Hours", "Swiftwater"]
  defp incident_tags(_title), do: ["Primary Hours"]

  # The newest incident, still a draft, has no file number yet: Required fields finds it.
  defp incident_values(title, days, n) do
    agency = Enum.at(["Police", "Ambulance", "Fire"], rem(n, 3))

    values = %{
      "#{@agency}" => [agency_option(agency)],
      "#{@task_type}" => [title |> task_type() |> task_option()],
      "#{@people_helped}" => @helped |> Map.get(title, 1) |> Integer.to_string()
    }

    values = if @notes[title], do: Map.put(values, "#{@team_notes}", @notes[title]), else: values

    if days == 3,
      do: values,
      else: Map.put(values, "#{@file_number}", "#{26 - div(days, 365)}-#{7310 - n * 37}")
  end

  defp task_type("Evidence search"), do: "Evidence search"
  defp task_type(title) when title in @rescues, do: "Rescue"
  defp task_type(_title), do: "Search"

  # A chore activity lasts no time: it starts and ends at midnight on the 1st (#575).
  defp chore_activities(today) do
    for month <- chore_months(today) do
      start = local(month, 0)

      %Activity{
        activity_kind: "event",
        title: Service.ChoreEventText.title("Hall and gear", month),
        description: "Made by SAR Duty from accepted chores.",
        started_at: start,
        finished_at: start,
        tags: ["Secondary Hours", "Chores"]
      }
    end
  end

  defp chore_months(today) do
    first = Date.beginning_of_month(today)
    for back <- 3..1//-1, do: Date.shift(first, month: -back)
  end

  defp usec(datetime), do: %{datetime | microsecond: {0, 6}}

  defp chore?(%Activity{tags: tags}), do: "Chores" in tags

  # Each member's reply to each activity they were on the team for, in a pattern rather
  # than at random, so a run is the same every time. Most attend; incidents fewer.
  defp attendances(activities, now, today) do
    for {activity, a} <- Enum.with_index(activities),
        not chore?(activity),
        {person, i} <- Enum.with_index(@people),
        row = attendance(activity, person, {a, i}, now, today),
        do: row
  end

  defp attendance(activity, {name, _, _, days, _, marks}, {a, i}, now, today) do
    with true <- on_team?(days, marks, activity, now),
         status when status != nil <- status(activity, rem(a * 7 + i * 3, 10), marks, now, today) do
      attendance_row(activity, name, status, {a, i}, now)
    else
      _none -> nil
    end
  end

  # A pager never attends.
  defp on_team?(days, marks, activity, now) do
    joined = DateTime.add(now, -days, :day)

    :not_a_person not in marks and DateTime.before?(joined, activity.started_at) and
      (:retired not in marks or now |> left_at() |> DateTime.after?(activity.started_at))
  end

  defp status(activity, score, marks, now, today) do
    on = local_date(activity.started_at)

    cond do
      :away in marks and Date.diff(on, today) in -10..20 -> "absent"
      # Sam stopped coming before joining Retiring.
      :retiring in marks and Date.diff(today, on) < 120 -> nil
      true -> reply(score, replies(activity, now))
    end
  end

  # Of every 10 members, how many attend, how many more are absent, and how many more have
  # yet to reply, which only a coming activity has.
  defp replies(activity, now) do
    cond do
      not Activity.started?(activity, now) -> {5, 7, 9}
      activity.activity_kind == "incident" -> {5, 7, 7}
      true -> {7, 9, 9}
    end
  end

  defp reply(score, {attending, absent, requested}) do
    cond do
      score < attending -> "attending"
      score < absent -> "absent"
      score < requested -> "requested"
      true -> nil
    end
  end

  defp local_date(datetime), do: datetime |> DateTime.shift_zone!(@timezone) |> DateTime.to_date()

  defp attendance_row(activity, name, status, {a, i}, now) do
    # Every sixth member who attended left half an hour early.
    early = if status == "attending" and rem(a + i, 6) == 0, do: 30, else: 0
    finished = DateTime.add(activity.finished_at, -early, :minute)
    minutes = DateTime.diff(finished, activity.started_at, :minute)

    row = %Attendance{
      d4h_attendance_id: 9_300_000 + a * 100 + i,
      status: status,
      started_at: activity.started_at,
      finished_at: finished,
      duration_in_minutes: minutes,
      replied_at: replied_at(activity, status, i, now)
    }

    {:attendance, {activity.d4h_activity_id, name}, row,
     member_id: {:member, name}, activity_id: {:activity, activity.d4h_activity_id}}
  end

  # Replies came in with #444: the coming activities, and those of the last two months.
  defp replied_at(%Activity{activity_kind: "incident"}, _status, _i, _now), do: nil
  defp replied_at(_activity, "requested", _i, _now), do: nil

  defp replied_at(activity, _status, i, now) do
    cond do
      not Activity.started?(activity, now) ->
        DateTime.add(now, -(i + 1), :hour)

      DateTime.diff(now, activity.started_at, :day) < 60 ->
        DateTime.add(activity.started_at, -(24 + i), :hour)

      true ->
        nil
    end
  end

  defp equipment(today) do
    for {{id, title, type, kind, status, holder}, n} <- Enum.with_index(@equipment, 1) do
      item = %EquipmentItem{
        d4h_equipment_id: id,
        title: title,
        item_type: type,
        kind: kind,
        status: status,
        barcode: "CR-" <> String.pad_leading("#{n}", 3, "0"),
        serial: "SN-#{id}",
        location_title: if(holder, do: nil, else: "Hall"),
        # The AED's pads.
        expires_at: if(title == "AED", do: noon(Date.add(today, 45))),
        custom_values: %{"#{@serviced}" => today |> Date.add(-30 * n) |> Date.to_iso8601()}
      }

      links = if holder, do: [member_id: {:member, holder}], else: []
      {:equipment_item, id, item, links}
    end
  end

  # The truck and a radio go to every incident, a rope kit to rope training, and throw
  # bags get used up at swiftwater training.
  defp equipment_usages(activities) do
    activities
    |> Enum.flat_map(&uses/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {{activity, item, use}, n} ->
      row = struct!(%EquipmentUsage{d4h_equipment_usage_id: 9_810_000 + n}, use)

      {:equipment_usage, n, row,
       activity_id: {:activity, activity.d4h_activity_id},
       equipment_item_id: {:equipment_item, item}}
    end)
  end

  defp uses(%Activity{activity_kind: "incident"} = activity) do
    minutes = DateTime.diff(activity.finished_at, activity.started_at, :minute)
    km = 20 + rem(activity.d4h_activity_id * 37, 100)

    [
      {activity, 9_800_001, minutes: minutes, distance: km},
      {activity, 9_800_002, minutes: minutes}
    ]
  end

  defp uses(%Activity{activity_kind: "exercise", title: "Rope rescue training"} = activity),
    do: [{activity, 9_800_006, minutes: 150}]

  defp uses(%Activity{activity_kind: "exercise", title: "Swiftwater training"} = activity),
    do: [{activity, 9_800_009, used: 2}]

  defp uses(_activity), do: []

  defp away_periods(today) do
    period = %MemberAwayPeriod{
      starts_on: Date.add(today, -10),
      ends_on: Date.add(today, 20),
      reason: "Travelling"
    }

    [{:away_period, "Dana Kowal", period, member_id: {:member, "Dana Kowal"}}]
  end

  # One chore category, its chores accepted onto a chore activity each month, and two
  # this month still waiting for a team admin.
  defp chores(activities, today) do
    category =
      {:chore_category, "Hall and gear",
       %ChoreCategory{
         title: "Hall and gear",
         description: "Cleaning the hall, checking packs, and looking after the truck.",
         hours: :secondary
       }, []}

    tag =
      {:chore_category_tag, "Chores", %ChoreCategoryTag{},
       chore_category_id: {:chore_category, "Hall and gear"}, tag_id: {:tag, "Chores"}}

    months =
      for month <- chore_months(today) do
        activity = Enum.find(activities, &(chore?(&1) and same_month?(&1, month)))
        month_chores(activity, month)
      end

    List.flatten([category, tag, months, waiting_chores(today)])
  end

  defp waiting_chores(today) do
    for {name, back, minutes, description} <- [
          {"Cameron Ruiz", 1, 60, "Restocked the snack bin."},
          {"Jordan Lee", 3, 45, "Charged the radios."}
        ] do
      chore = %Chore{
        date: Date.add(today, -back),
        minutes: minutes,
        description: description,
        status: :waiting
      }

      {:chore, {:waiting, name}, chore,
       member_id: {:member, name}, chore_category_id: {:chore_category, "Hall and gear"}}
    end
  end

  defp same_month?(activity, month),
    do: activity.started_at |> local_date() |> Date.beginning_of_month() == month

  defp month_chores(activity, month) do
    sent = month |> Date.shift(month: 1) |> Date.add(1) |> noon() |> usec()

    event =
      {:chore_event, month,
       %ChoreEvent{month: month, d4h_activity_id: activity.d4h_activity_id, sent_at: sent},
       chore_category_id: {:chore_category, "Hall and gear"}}

    rows =
      for {chore, i} <- Enum.with_index(@chores),
          do: accepted_chore(chore, i, activity, month, sent)

    [event | rows]
  end

  # An accepted chore, and its member's row on the month's chore activity.
  defp accepted_chore({name, day, minutes, description}, i, activity, month, sent) do
    chore = %Chore{
      date: Date.new!(month.year, month.month, day),
      minutes: minutes,
      description: description,
      status: :accepted,
      decided_at: sent
    }

    attendance = %Attendance{
      d4h_attendance_id: 9_390_000 + activity.d4h_activity_id - 9_200_000 + i * 1000,
      status: "attending",
      started_at: activity.started_at,
      finished_at: DateTime.add(activity.started_at, minutes, :minute),
      duration_in_minutes: minutes
    }

    [
      {:chore, {month, name}, chore,
       member_id: {:member, name},
       chore_category_id: {:chore_category, "Hall and gear"},
       chore_event_id: {:chore_event, month}},
      {:attendance, {activity.d4h_activity_id, name}, attendance,
       member_id: {:member, name}, activity_id: {:activity, activity.d4h_activity_id}}
    ]
  end
end
