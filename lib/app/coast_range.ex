defmodule App.CoastRange do
  @moduledoc """
  Coast Range SAR (CRSAR), the made-up team (#816): the cast every mockup draws
  (docs/mockups.md), and the team an agent's report runs on (App.SampleRepo). Never a
  real person, team, or number: names, ref ids, and 604-555-01xx phone numbers never
  change, and every date counts back from `now`. Its place names are made up too: the
  team is in Cedar Creek BC. Only the map points are real, so maps and mileage work.

  It fills every field a report reads: a year of activities of each kind with tags,
  hours tags, tracking numbers, drafts, and a missing required field; attendance
  attended, absent, and signed up for the coming week; groups, with a Retiring one;
  qualifications and awards, some expiring, and the endorsements ID cards list;
  equipment and its use; chores; an away member, a retired one, and one that isn't a
  person; and the sample ID cards the verify site's /samples page shows (#854). Its
  incidents carry BCSARA's 27 incident fields with made-up values (#950), so a BC form
  tried here fills every line.

  It also stages what a demo shows off, so each feature has something to see the moment
  it opens: whiteboard notes, saved places, templates, group rules with changes to
  review, and travel set on the two draft incidents, with homes and routes saved so
  mileage never asks Mapbox.

  Pure: build/2 is rows, and App.Operation.SeedCoastRange inserts them. Try a demo
  (App.DemoCast) passes a visitor, who joins as a team leader with a history of their own.

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
  - **Zoë Lefèvre**, ground searcher: an accented name, with attended hours, so she gets
    a tax letter. Her email is plain letters: zoe.lefevre@example.com.
  - **The visitor**, only in a demo: a team admin beside Alex, a team leader for 1600
    days, keyed `{:member, :visitor}`. Attended Missing hiker, where a team admin set
    their travel for them to confirm; first aid expires in 30 days; an ID card not yet
    in Wallet; and no reply yet to anything coming up.

  Activities, by title: **Missing hiker** is the newest incident, a draft missing its
  Agency File #; **Trail safety booth** is an event in 4 days; the coming Tuesday's
  training has sign-ups, can't-make-its, and no replies; **Night search exercise** is in
  12 days; **Evidence search** has no hours tag and **Missing hunter** has both.

  Travel: on **Missing hiker** a team admin set most rows, some members confirmed, and
  two rows aren't set; on **Overdue kayakers** every row is set and confirmed, ready to
  copy into D4H and publish.

  Group rules: **Callout** is everyone with Ground search and rescue who is active, so
  its review takes off Dana, who is away; **Swiftwater team** is everyone holding a
  current swiftwater ticket, so its review takes off Priya, whose ticket expired.
  """

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreCategoryTag
  alias App.Model.ChoreEvent
  alias App.Model.Coordinate
  alias App.Model.CustomField
  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRule
  alias App.Model.GroupRuleReference
  alias App.Model.HomeCoordinate
  alias App.Model.LocationBookmark
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCard
  alias App.Model.MemberQualificationAward
  alias App.Model.Organization
  alias App.Model.Qualification
  alias App.Model.RouteDistance
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Model.Template
  alias App.Model.TemplateGroup
  alias App.Model.TemplateItem
  alias App.Model.TemplateTag
  alias App.Model.Trip
  alias App.Model.WhiteboardNote

  # BCEHS is BC Emergency Health Services, an agency in BCSARA's Agency field.
  # cspell:ignore BCEHS CRSAR Kowal Noor Priya Okafor

  @timezone "America/Vancouver"
  @d4h_team_id 9_100_000
  # The team's own place, its yard for mileage.
  @yard_lat 49.2
  @yard_lng -123.1

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
    {"Duty pager", "145", "604-555-0135", 2000, nil, [:not_a_person]},
    {"Zoë Lefèvre", "147", "604-555-0137", 700, "Ground searcher", []}
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

  # D4H's costs in whole cents, per km, per hour, and per use, as EMCR's claim reads them
  # (#950). Others have none.
  @costs %{
    9_800_001 => {67, 0, 0},
    9_800_002 => {nil, 1500, nil},
    9_800_006 => {nil, 3000, nil},
    9_800_009 => {nil, nil, 2500}
  }

  # Each month's accepted chores: who, the day, minutes, and what.
  @chores [
    {"Priya Nair", 5, 90, "Checked the first aid packs."},
    {"Noor Aziz", 12, 120, "Washed and fuelled the truck."},
    {"Cameron Ruiz", 19, 60, "Swept the hall."},
    {"Alex Chen", 26, 180, "Sorted the rope cache."}
  ]

  @agency 9_400_001
  @call_sign 9_400_003
  @serviced 9_400_004
  @people_helped 9_400_006
  @team_notes 9_400_007
  @exercise_leader 9_400_008
  @event_leader 9_400_009
  @areas 9_400_010
  @birth_year 9_400_011

  # Each incident's people helped, and a team admin's notes (RESTRICTED).
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
  # BCSARA's incident fields (#950), as D4H gives every BC team its organization's, so
  # trying a BC form here fills every line. Titles, types, required, and order are
  # BCSARA's; option lists keep only the options Coast Range SAR uses, since
  # App.SampleRepoTest wants each one somewhere. Ids from
  # 9_400_401 in this order, and each option's id is its field's times 100 plus its
  # place.
  @bcsara_owner 9_100_100
  @severity [
    "Category 1 - Life in Imminent Danger",
    "Category 2 - Subject in grave or imminent danger",
    "Category 3 - Assistance required, subject not in grave or Imminent danger or not in distress"
  ]
  @bcsara_fields [
    {"What was SAR tasked to do?", "single_choice", true,
     [
       "Rescue - injury & medical emergency",
       "Rescue - stuck or 'lost' subject(s)",
       "Search - lost subject(s)",
       "Evidence search"
     ]},
    {"How many people were in the group that requested help?", "number", true, []},
    {"How many people received assistance from SAR?", "text", true, []},
    {"Response Type", "single_choice", true, ["Call-Out", "Response"]},
    {"Agency", "single_choice", true, ["Police", "BCEHS", "Fire"]},
    {"Police Department", "single_choice", false, ["RCMP - Royal Canadian Mounted Police"]},
    {"Agency File #", "text", true, []},
    {"ASE#", "text", false, []},
    {"Region", "single_choice", true, ["South West"]},
    {"Area", "text", true, []},
    {"Task Type", "single_choice", true,
     [
       "002 - Land SAR",
       "003 - Inland water SAR",
       "020 - Cliff rescue",
       "021 - Mountain rescue"
     ]},
    {"Equipment Used/Lost", "text", false, []},
    {"Task Leader's Name", "text", true, []},
    {"Date Report Completed", "date", true, []},
    {"Was RADeMS Discussed?", "single_choice", true, ["YES", "NO"]},
    {"Was a Level 2 SAR Manager Activated for this Incident?", "single_choice", true,
     ["Yes", "No"]},
    {"SAR Severity", "single_choice", true, @severity},
    {"Activity", "single_choice", true,
     [
       "L - Biking (mountain or trail; pedal powered)",
       "L - Camping",
       "L - Climbing (alpine)",
       "L - Driving (car/truck)",
       "L - Gathering/picking (fruit/plants)",
       "L - Hiking",
       "L - Hunting",
       "L - Skiing (alpine or backcountry)",
       "L - Snowshoeing",
       "M - Boating (paddling: canoe/kayak/SUP)",
       "M - Swimming",
       "X - Not applicable",
       "Z - Unknown activity"
     ]},
    {~s(If Activity = "Other" or "N/A" Describe:), "text", false, []},
    {"Primary Cause", "single_choice", true,
     [
       "Current/High waves/Tides",
       "Injury",
       "Loss of Control/crash",
       "Lost/disoriented",
       "Onset of darkness",
       "Other (Specify)",
       "Separation",
       "Severe weather",
       "Slip or fall",
       "Stranded",
       "Unknown"
     ]},
    {"Secondary Cause", "single_choice", false,
     ["N/A - No secondary cause)", "Fatigue/exhaustion", "Exceeded ability"]},
    {~s(If either cause = "Other" or "N/A" Describe:), "text", false, []},
    {"Was weather a factor in response?", "single_choice", true, ["YES", "NO"]},
    {"Alert Type", "single_choice", true,
     [
       "Concerned citizen",
       "Concerned family member",
       "Request from other SAR authority",
       "Telephone - cellular"
     ]},
    {"Mutual Aid Requested?", "single_choice", true, ["YES", "NO"]},
    {"Evacuation notices delivered", "number", false, []},
    {"Households evacuated", "number", false, []}
  ]
  # BCSARA's own hints, as D4H gives them, so the fields read as a real team's do.
  # cspell:ignore RADeMS
  @bcsara_hints %{
    "What was SAR tasked to do?" =>
      "Rescue for a 'lost' subject does not require a SAR search.\nSearch for a lost subject requires SAR to search.",
    "How many people were in the group that requested help?" => "If unknown, enter 999",
    "How many people received assistance from SAR?" =>
      "Assistance may be first aid, evacuation, supplies (e.g., warm clothes, a headlamp, food), directions to the trail, etc.\n\nIf unknown, enter 999.",
    "Response Type" =>
      "'Call-out' -> when the SAR Group was activated, but did NOT deploy resources into the field. This includes instances where members/vehicles where en route to a staging point, but were stood down BEFORE a command post was established.\n\n'Response' -> SAR resources deployed into the Field.",
    "Agency" => "Choose an approved 'requesting agency' from the list",
    "Police Department" =>
      "If 'Police' was selected under 'Agency', please select which department was the requesting agency.",
    "Agency File #" => "The file # of the requesting agency",
    "ASE#" =>
      "ASE# is issued by EMBC to approve use of an aircraft, typically a helicopter. See EMBC policy for restrictions on use of helicopters.",
    "Region" => "Select the EMBC region (not the BCSARA region) that the incident occurred in.",
    "Area" =>
      "'Area' means location of incident. Enter general description of the location. e.g. 'Fraser River, near Hope'",
    "Task Type" => "Select one task type",
    "Equipment Used/Lost" =>
      "Enter a brief description of equipment used, lost and/or damaged. For damaged or lost equipment complete a separate 'Equipment Repair/Replacement' (ERR) form and submit to EMBC",
    "Task Leader's Name" => "The Task Leader is the point of contact for the Task Report",
    "Date Report Completed" => "Enter the date that this report was completed",
    "Was a Level 2 SAR Manager Activated for this Incident?" =>
      "Only to be used if the incident moves into multi-operational periods requiring a Level 2 SAR manager. Only the initiating team selects 'Yes'. If a Level 2 was not required select No. If you are a mutual aid group, or the level 2 SAR manager from a mutual aid group select N/A.",
    "SAR Severity" =>
      "Category 1: Highest urgency. Subject's life is at imminent risk and will not survive if SAR does not intervene.\n\nCategory 2: Urgent. Subject is in grave or imminent danger requiring SAR intervention.\n\nCategory 3: Least urgent. Situation is objectively not presenting imminent or grave danger to the subject. Subject requires assistance to resolve their situation and/or may be personally experiencing distress (e.g., frightened, anxious).",
    "Activity" =>
      "The activity that was taking place when the incident occurred. Organized by Air, Land, Marine, or Working. Select the activity in which the subject was engaged when the incident occurred. For example: if the subject became lost hiking to a campsite, the activity is hiking.",
    ~s(If Activity = "Other" or "N/A" Describe:) =>
      "To help identify gaps in data options, please provide additional information if no suitable activity types are available.",
    "Primary Cause" => "The primary cause of the incident.",
    "Secondary Cause" => "The secondary cause of the incident.",
    ~s(If either cause = "Other" or "N/A" Describe:) =>
      "To support identification of data gaps, please provide additional information about the cause if no suitable options exist.",
    "Was weather a factor in response?" =>
      "Indicates whether the weather was a significant factor in the response",
    "Alert Type" =>
      "What prompted the task initially (e.g. how was the subjects situation made known to tasking agency?).",
    "Mutual Aid Requested?" =>
      "Only answer 'YES' or 'NO' if you were the PRIMARY SAR Group that responded to the incident.\n\nIf you responded as a 'Mutual Assistance' SAR group, select 'N/A - Mutual Assistance Only'",
    "Evacuation notices delivered" => "How many households were delivered evacuation notices?",
    "Households evacuated" => "How many households were evacuated?"
  }
  # Each incident's answers to BCSARA's fields: what SAR was tasked to do, the task type,
  # the subject's activity, the primary cause, the alert, and the severity's category.
  @bcsara_incidents %{
    "Missing hiker" =>
      {"Search - lost subject(s)", "002 - Land SAR", "L - Hiking", "Lost/disoriented",
       "Concerned family member", 3},
    "Overdue kayakers" =>
      {"Search - lost subject(s)", "003 - Inland water SAR",
       "M - Boating (paddling: canoe/kayak/SUP)", "Severe weather", "Concerned family member", 2},
    "Injured mountain biker" =>
      {"Rescue - injury & medical emergency", "002 - Land SAR",
       "L - Biking (mountain or trail; pedal powered)", "Injury", "Telephone - cellular", 2},
    "Lost child, day-use area" =>
      {"Search - lost subject(s)", "002 - Land SAR", "L - Camping", "Separation",
       "Concerned family member", 2},
    "Missing hunter" =>
      {"Search - lost subject(s)", "002 - Land SAR", "L - Hunting", "Lost/disoriented",
       "Concerned family member", 3},
    "Stranded skiers" =>
      {"Rescue - stuck or 'lost' subject(s)", "021 - Mountain rescue",
       "L - Skiing (alpine or backcountry)", "Stranded", "Telephone - cellular", 3},
    "Fallen climber" =>
      {"Rescue - injury & medical emergency", "020 - Cliff rescue", "L - Climbing (alpine)",
       "Slip or fall", "Telephone - cellular", 2},
    "Missing person, river" =>
      {"Search - lost subject(s)", "003 - Inland water SAR", "Z - Unknown activity", "Unknown",
       "Request from other SAR authority", 2},
    "Evidence search" =>
      {"Evidence search", "002 - Land SAR", "X - Not applicable", "Other (Specify)",
       "Request from other SAR authority", 3},
    "Overdue snowshoers" =>
      {"Search - lost subject(s)", "002 - Land SAR", "L - Snowshoeing", "Onset of darkness",
       "Concerned family member", 3},
    "Vehicle over the bank" =>
      {"Rescue - injury & medical emergency", "020 - Cliff rescue", "L - Driving (car/truck)",
       "Loss of Control/crash", "Telephone - cellular", 2},
    "Injured hiker, carry-out" =>
      {"Rescue - injury & medical emergency", "002 - Land SAR", "L - Hiking", "Injury",
       "Telephone - cellular", 3},
    "Missing berry picker" =>
      {"Search - lost subject(s)", "002 - Land SAR", "L - Gathering/picking (fruit/plants)",
       "Lost/disoriented", "Concerned family member", 3},
    "Swiftwater rescue" =>
      {"Rescue - stuck or 'lost' subject(s)", "003 - Inland water SAR", "M - Swimming",
       "Current/High waves/Tides", "Concerned citizen", 1}
  }
  @areas_options ["Fundraising", "Training", "Public education", "Vehicle care"]
  @member_areas %{
    "Cameron Ruiz" => ["Fundraising", "Public education"],
    "Priya Nair" => ["Training", "Vehicle care"],
    "Noor Aziz" => ["Vehicle care"],
    "Casey Dhillon" => ["Fundraising"]
  }
  # A RESTRICTED member field, which SAR Duty keeps like any other (#1056).
  @birth_years %{"Cameron Ruiz" => "1988", "Priya Nair" => "1979", "Alex Chen" => "1975"}
  @leaders ["Alex Chen", "Harper Nguyen", "Avery Chen"]

  @doc "Coast Range SAR's time zone."
  def timezone, do: @timezone

  @doc "Every member's name, Alex Chen first."
  def names, do: Enum.map(@people, &elem(&1, 0))

  @doc """
  Pure. Coast Range SAR as of `now`: rows `{kind, key, struct, links}` in the order they
  insert. `links` names each foreign key's row as `{field, {kind, key}}`; every row but
  the team's also gets the team's id. `visitor: %{name:, email:}` adds a demo's visitor
  as a member, `{:member, :visitor}`.
  """
  def build(%DateTime{} = now, opts \\ []) do
    now = DateTime.truncate(now, :second)
    today = Service.Period.today(now, @timezone)
    people = people(opts[:visitor])
    activities = activities(now, today)
    attendances = attendances(people, activities, now, today)

    Enum.concat([
      [{:team, :coastrange, team(now), []}],
      tags(),
      custom_fields(),
      people_rows(people, opts[:visitor], now, today),
      Enum.map(activities, &{:activity, &1.d4h_activity_id, &1, []}),
      attendances,
      equipment(today),
      equipment_usages(activities),
      away_periods(today),
      chores(activities, today),
      staged(now),
      travel(people, activities, attendances, now)
    ])
  end

  defp people_rows(people, visitor, now, today) do
    Enum.concat([
      members(people, visitor, now),
      groups(people),
      qualifications(people, today),
      endorsements(),
      group_rules(),
      member_cards(people, now)
    ])
  end

  defp staged(now), do: whiteboard_notes(now) ++ location_bookmarks() ++ templates()

  defp travel(people, activities, attendances, now) do
    homes = homes(people)

    home_coordinates(people, homes) ++
      route_distances(homes) ++ trips(activities, attendances, homes, now)
  end

  # The cast, and a demo's visitor after them: a team leader and an Owner like Alex.
  defp people(nil), do: @people

  defp people(%{}),
    do:
      List.insert_at(
        @people,
        -1,
        {:visitor, "146", "604-555-0136", 1600, "Team leader", [:owner, :visitor]}
      )

  @doc """
  Coast Range SAR's organization, made up like the team (#963): Western Search and Rescue
  Association, said "we-SAR-ah", with Silver Basin SAR (App.SilverBasin) as its second
  team. App.SampleRepo seeds it, for reports' organization subject (#918), and so do the
  dev teams; each demo gets a copy of its own, slug `wesara-<demo id>`. Mockups seed the
  cast more than once, so they leave it out: its slug is unique.
  """
  def organization do
    %Organization{
      name: "Western Search and Rescue Association",
      short_name: "WESARA",
      slug: "wesara",
      website: "https://example.org"
    }
  end

  @doc "WESARA's made-up logo, a 480-pixel PNG: mountains and an orange cross."
  def organization_logo_file, do: Application.app_dir(:sarduty, "priv/demo/wesara-logo.png")

  @doc """
  WESARA's organization admins, `%{name:, title:, email:}`: neither belongs to a team. Not
  Taylor Brooks, a demo visitor's default name.
  """
  def organization_admins do
    for {name, title} <- [
          {"Morgan Ellis", "Executive director"},
          {"Rowan Pike", "Office manager"}
        ],
        do: %{name: name, title: title, email: email(name)}
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
      city: "Cedar Creek BC",
      postal_code: "V5K 0A1",
      authorized_by_name: "Alex Chen",
      authorized_by_title: "President",
      authorized_by_phone: "604-555-0112",
      authorized_by_email: email("Alex Chen"),
      lat: @yard_lat,
      lng: @yard_lng,
      timezone: @timezone,
      member_logins: true,
      chores_enabled: true,
      certificates_enabled: true,
      id_cards_enabled: true,
      whiteboard_enabled: true,
      travel_enabled: true,
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

    # Hints in the style of a real team's, South Fraser SAR's.
    [
      custom_field(@agency, "incident", "Requesting agency", "single_choice",
        required: true,
        hint: "The agency that asked for SAR. Choose one from the list.",
        options: agency_options
      ),
      custom_field(@call_sign, "member", "Radio call sign", "text",
        member_privacy: "viewable",
        hint: "Radio call sign (if assigned own radio)"
      ),
      custom_field(@serviced, "equipment", "Last serviced", "date",
        hint: "The date this item was last serviced or inspected."
      ),
      custom_field(@people_helped, "incident", "People helped", "number",
        hint: "For the team's year-end report. If unknown, enter 999.",
        value_units: "people"
      ),
      custom_field(@team_notes, "incident", "Team notes", "text_area",
        restricted: true,
        hint: "For private notes etc. Does not roll up to WESARA."
      ),
      # The same title on two kinds: a report reads it as one field.
      custom_field(@exercise_leader, "exercise", "Event leader", "text",
        hint: "The member running the training, for the training record."
      ),
      custom_field(@event_leader, "event", "Event leader", "text",
        hint: "The member running the event, who answers questions about it."
      ),
      custom_field(@areas, "member", "Areas of assistance", "multiple_choice",
        member_privacy: "editable",
        hint: "Please fill this out with areas you can help with",
        options: options(@areas_options, &area_option/1)
      ),
      custom_field(@birth_year, "member", "Year of birth", "number",
        member_privacy: "editable",
        restricted: true,
        hint: "In what year were you born?"
      )
    ] ++ organization_fields()
  end

  # BCSARA's 5 fields on each of its teams (#1056 step 5), with made-up hints, from
  # 9_400_501 in this order. No team has values: a team admin fills them in on General.
  @team_fields [
    {"Duty Phone", "text", "The number an agency calls to reach the team."},
    {"Mailing Address", "text_area", nil},
    {"City/Town", "text", nil},
    {"Postal Code", "text", nil},
    {"Team Email Contact", "text", "Where the association writes to the team."}
  ]

  @doc """
  WESARA's 27 incident fields, BCSARA's, and its 5 on the team itself, as `{:custom_field,
  id, field, []}` rows owned by the organization, as D4H gives them to each of its teams.
  Silver Basin SAR has them too.
  """
  def organization_fields, do: incident_fields() ++ team_fields()

  defp team_fields do
    for {{title, type, hint}, i} <- Enum.with_index(@team_fields) do
      custom_field(9_400_501 + i, "team", title, type,
        hint: hint,
        ordering: i,
        owner_type: "Organisation",
        owner_id: @bcsara_owner
      )
    end
  end

  defp incident_fields do
    for {{title, type, required, labels}, i} <- Enum.with_index(@bcsara_fields) do
      id = bcsara_id(title)
      options = for {label, j} <- Enum.with_index(labels), do: {label, id * 100 + j}

      field =
        custom_field(id, "incident", title, type,
          required: required,
          hint: @bcsara_hints[title],
          ordering: 100 + i,
          owner_type: "Organisation",
          owner_id: @bcsara_owner
        )

      with_options(field, options)
    end
  end

  defp with_options(field, []), do: field

  defp with_options(field, options),
    do: put_elem(field, 2, %{elem(field, 2) | options: option_maps(options)})

  defp option_maps(options) do
    for {{label, id}, i} <- Enum.with_index(options),
        do: %{"id" => id, "label" => label, "ordering" => i, "archived" => false}
  end

  defp bcsara_id(title) do
    case Enum.find_index(@bcsara_fields, &(elem(&1, 0) == title)) do
      nil -> raise ArgumentError, "BCSARA has no field #{title}"
      i -> 9_400_401 + i
    end
  end

  @doc """
  Values for WESARA's fields (organization_fields/0), from `{title, value}` pairs: an
  option's label for a choice, or the text. A nil value is left out.
  """
  def organization_values(pairs) do
    for {title, value} <- pairs, value != nil, into: %{}, do: bcsara_value(title, value)
  end

  # A value for BCSARA's field `title`: an option's id in a list, or the text.
  defp bcsara_value(title, value) do
    {^title, _type, _required, labels} = List.keyfind(@bcsara_fields, title, 0)

    case Enum.find_index(labels, &(&1 == value)) do
      nil when labels == [] -> {"#{bcsara_id(title)}", value}
      nil -> raise ArgumentError, "BCSARA's #{title} has no option #{value}"
      j -> {"#{bcsara_id(title)}", [bcsara_id(title) * 100 + j]}
    end
  end

  defp options(labels, id) do
    for {label, i} <- Enum.with_index(labels) do
      %{"id" => id.(label), "label" => label, "ordering" => i, "archived" => false}
    end
  end

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

  defp members(people, visitor, now),
    do: Enum.map(people, &(&1 |> member(visitor, now) |> put_photo()))

  defp member({key, ref_id, phone, days, position, marks}, visitor, now) do
    person? = :not_a_person not in marks
    retired? = :retired in marks
    {name, email} = name_and_email(key, visitor)

    member = %Member{
      d4h_member_id: 9_110_000 + String.to_integer(ref_id),
      ref_id: ref_id,
      name: name,
      email: if(person?, do: email),
      phone: phone,
      address: address(ref_id, marks),
      position: position,
      joined_at: day_start(now, -days),
      d4h_permission: permission(marks),
      d4h_status: if(retired?, do: "RETIRED", else: "OPERATIONAL"),
      left_at: if(retired?, do: left_at(now)),
      not_a_person: not person?,
      custom_values: member_values(key, ref_id)
    }

    {:member, key, member, []}
  end

  # Each person has the sample photo but the visitor, as DemoCast sends them (#1012).
  defp put_photo({:member, :visitor, _member, _links} = row), do: row

  defp put_photo({:member, key, member, links}),
    do: {:member, key, %{member | has_photo: not member.not_a_person}, links}

  defp address(ref_id, marks) do
    if :not_a_person in marks or :no_address in marks, do: nil, else: "#{ref_id} Example Road"
  end

  defp name_and_email(:visitor, visitor), do: {visitor.name, visitor.email}
  defp name_and_email(name, _visitor), do: {name, email(name)}

  @doc """
  A cast member's made-up email, in plain letters: "Zoë Lefèvre" is
  zoe.lefevre@example.com, "Siobhán O'Connor-Hale" siobhan.oconnor-hale@example.com.
  """
  def email(name) do
    local =
      name
      |> String.replace(["Ł", "ł"], "l")
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9 -]/, "")
      |> String.replace(" ", ".")

    "#{local}@example.com"
  end

  defp left_at(now), do: day_start(now, -120)

  # A day D4H keeps without a time, `days` from today, as the copy stores it: the start
  # of that day on the team's clock (docs/d4h-sync.md).
  defp day_start(now, days),
    do: now |> Service.Period.today(@timezone) |> Date.add(days) |> day_start()

  defp day_start(%Date{} = date), do: Service.Convert.day_start(date, @timezone)

  defp member_values(name, ref_id) do
    values = %{"#{@call_sign}" => "CR #{ref_id}"}

    values =
      case @birth_years[name] do
        nil -> values
        year -> Map.put(values, "#{@birth_year}", year)
      end

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

  defp person(people, name), do: Enum.find(people, &(elem(&1, 0) == name))

  # On the team now and a person: everyone a group of all, or an award, holds.
  defp current_people(people),
    do:
      for(
        {name, _, _, _, _, marks} <- people,
        :retired not in marks,
        :not_a_person not in marks,
        do: name
      )

  defp groups(people) do
    for {d4h_id, title, names} <- @groups do
      names = group_names(people, title, names)

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

  defp visitor?(people), do: person(people, :visitor) != nil

  # The visitor's first aid expires in 30 days, so their Dashboard asks them to renew it.
  defp visitor_awards(people, 9_600_002), do: if(visitor?(people), do: [{:visitor, 30}], else: [])

  defp visitor_awards(people, 9_600_005),
    do: if(visitor?(people), do: [{:visitor, 900}], else: [])

  defp visitor_awards(_people, _d4h_id), do: []

  defp group_names(people, _title, :all),
    do: current_people(people) -- ["Riley Okafor", "Sam Rivera"]

  # The visitor leads, beside Alex.
  defp group_names(people, "Team leaders", names),
    do: if(visitor?(people), do: List.insert_at(names, -1, :visitor), else: names)

  defp group_names(_people, _title, names), do: names

  defp qualifications(people, today) do
    for {d4h_id, title, months, holders} <- @qualifications do
      holders = if is_list(holders), do: holders ++ visitor_awards(people, d4h_id), else: holders

      qualification =
        {:qualification, d4h_id,
         %Qualification{
           d4h_qualification_id: d4h_id,
           title: title,
           expires_months_default: months
         }, []}

      [qualification | awards(people, d4h_id, months, holders, today)]
    end
    |> List.flatten()
  end

  # Ground search and rescue never expires, and comes two months after joining.
  defp awards(people, d4h_id, nil, :all, today) do
    for {name, i} <- Enum.with_index(current_people(people) -- ["Riley Okafor"], 1) do
      {_, _, _, days, _, _} = person(people, name)
      award(d4h_id, name, i, Date.add(today, 60 - days), nil)
    end
  end

  defp awards(_people, d4h_id, months, holders, today) do
    for {{name, expires_in}, i} <- Enum.with_index(holders, 1) do
      ends = Date.add(today, expires_in)
      award(d4h_id, name, i, Date.shift(ends, month: -months), ends)
    end
  end

  defp award(d4h_id, name, i, starts, ends) do
    row = %MemberQualificationAward{
      d4h_award_id: d4h_id * 100 + i,
      starts_at: day_start(starts),
      ends_at: ends && day_start(ends)
    }

    {:award, {d4h_id, name}, row,
     member_id: {:member, name}, qualification_id: {:qualification, d4h_id}}
  end

  # The endorsements ID cards list, each earned by one qualification, and Swiftwater, which
  # only a group rule uses.
  @endorsements [
    {"First aid", 9_600_002, true},
    {"Ground search and rescue", 9_600_001, true},
    {"Swiftwater", 9_600_004, false}
  ]

  defp endorsements do
    for {name, d4h_qualification_id, on_card} <- @endorsements do
      [
        {:endorsement, name, %Endorsement{name: name, on_card: on_card}, []},
        {:endorsement_qualification, name,
         %EndorsementQualification{d4h_qualification_id: d4h_qualification_id},
         endorsement_id: {:endorsement, name}}
      ]
    end
    |> List.flatten()
  end

  @doc """
  The sample ID cards (#854): what each shows on the verify site, its stored code, and
  whose it is. `SAMPXNCRDX` matches no card, for "No card has this code". Codes start with
  `SAMP`, which MemberCard.generate_code/0 never makes, and the verify site looks them up
  in App.SampleRepo only.
  """
  def sample_cards do
    [
      %{status: :active, code: "SAMPXACTVX", member: "Cameron Ruiz"},
      %{status: :inactive, code: "SAMPXRTRDX", member: "Robin Tse"},
      %{status: :revoked, code: "SAMPXCNCDX", member: "Cameron Ruiz"},
      %{status: :not_found, code: "SAMPXNCRDX", member: nil}
    ]
  end

  # The cancelled card is Cameron's last one, replaced a month ago, so it goes first.
  # The visitor's card has no code: the demo gives it a real one (App.Operation.BuildDemoTeam).
  defp member_cards(people, now) do
    revoked_at = now |> DateTime.add(-30, :day) |> usec()

    samples =
      for %{member: name} = sample <- Enum.sort_by(sample_cards(), &(&1.status != :revoked)),
          name != nil do
        card = %MemberCard{
          code: sample.code,
          serial_number: "coastrange-#{ref_id(people, name)}",
          revoked_at: if(sample.status == :revoked, do: revoked_at)
        }

        {:member_card, sample.code, card, member_id: {:member, name}}
      end

    visitor =
      if visitor?(people),
        do: [
          {:member_card, :visitor,
           %MemberCard{serial_number: "coastrange-#{ref_id(people, :visitor)}"},
           member_id: {:member, :visitor}}
        ],
        else: []

    samples ++ visitor
  end

  defp ref_id(people, name), do: people |> person(name) |> elem(1)

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
        custom_values: incident_values(title, days, n, today),
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
  # Trail country on land, never water: Grouse, Lynn Headwaters, Mount Seymour, Cypress,
  # Burnaby Mountain, and Burke Mountain. The newest incident, Missing hiker, is Grouse.
  @incident_places [
    "49.38000,-123.08000",
    "49.38500,-123.02500",
    "49.36600,-122.94800",
    "49.39500,-123.20000",
    "49.27800,-122.91700",
    "49.32000,-122.73000"
  ]

  defp incident_place(n), do: Enum.at(@incident_places, rem(n, length(@incident_places)))

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

  # The newest incident, still a draft, has no Agency File # yet: Required fields finds it.
  defp incident_values(title, days, n, today) do
    agency = Enum.at(["Police", "Ambulance", "Fire"], rem(n, 3))
    helped = @helped |> Map.get(title, 1) |> Integer.to_string()

    values = %{
      "#{@agency}" => [agency_option(agency)],
      "#{@people_helped}" => helped
    }

    values = if @notes[title], do: Map.put(values, "#{@team_notes}", @notes[title]), else: values
    file_number = if days != 3, do: "#{26 - div(days, 365)}-#{7310 - n * 37}"

    title
    |> bcsara_values(agency, helped, file_number, today |> Date.add(1 - days), n)
    |> organization_values()
    |> Map.merge(values)
  end

  defp bcsara_values(title, agency, helped, file_number, reported, n) do
    {tasked, task_type, activity, cause, alert, severity} = Map.fetch!(@bcsara_incidents, title)
    agency = if agency == "Ambulance", do: "BCEHS", else: agency
    other = if activity == "X - Not applicable", do: "Line search of a field for police."

    [
      {"What was SAR tasked to do?", tasked},
      {"How many people were in the group that requested help?", helped},
      {"How many people received assistance from SAR?", helped},
      {"Response Type", if(title == "Missing person, river", do: "Call-Out", else: "Response")},
      {"Agency", agency},
      {"Police Department", if(agency == "Police", do: "RCMP - Royal Canadian Mounted Police")},
      {"Agency File #", file_number},
      {"ASE#", "ASE-#{4113 - n}"},
      {"Region", "South West"},
      {"Area", "Cedar Creek"},
      {"Task Type", task_type},
      {"Equipment Used/Lost", equipment_used(task_type)},
      {"Task Leader's Name", Enum.at(@leaders, rem(n, 3))},
      {"Date Report Completed", Date.to_iso8601(reported)},
      {"Was RADeMS Discussed?", if(tasked == "Evidence search", do: "NO", else: "YES")},
      {"Was a Level 2 SAR Manager Activated for this Incident?",
       if(title == "Missing hunter", do: "Yes", else: "No")},
      {"SAR Severity", Enum.at(@severity, severity - 1)},
      {"Activity", activity},
      {~s(If Activity = "Other" or "N/A" Describe:), other},
      {"Primary Cause", cause},
      {"Secondary Cause", secondary_cause(title)},
      {~s(If either cause = "Other" or "N/A" Describe:), other},
      {"Was weather a factor in response?", if(cause == "Severe weather", do: "YES", else: "NO")},
      {"Alert Type", alert},
      {"Mutual Aid Requested?", if(title == "Missing person, river", do: "YES", else: "NO")},
      {"Evacuation notices delivered", "0"},
      {"Households evacuated", "0"}
    ]
  end

  defp secondary_cause("Overdue snowshoers"), do: "Fatigue/exhaustion"
  defp secondary_cause("Stranded skiers"), do: "Exceeded ability"
  defp secondary_cause(_title), do: "N/A - No secondary cause)"

  defp equipment_used("020 - Cliff rescue"), do: "Rope kit B and stretcher. Nothing lost."
  defp equipment_used("003 - Inland water SAR"), do: "Throw bags and drysuits. Nothing lost."
  defp equipment_used(_task_type), do: "Radios and first aid kit. Nothing lost."

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
  defp attendances(people, activities, now, today) do
    for {activity, a} <- Enum.with_index(activities),
        not chore?(activity),
        {person, i} <- Enum.with_index(people),
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
      :visitor in marks -> visitor_status(activity, score, now)
      :away in marks and Date.diff(on, today) in -10..20 -> "absent"
      # Sam stopped coming before joining Retiring.
      :retiring in marks and Date.diff(today, on) < 120 -> nil
      true -> reply(score, replies(activity, now))
    end
  end

  # The visitor has yet to reply to what's coming, and was at the newest incident.
  defp visitor_status(activity, score, now) do
    cond do
      not Activity.started?(activity, now) -> "requested"
      activity.title == "Missing hiker" -> "attending"
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
        expires_at: if(title == "AED", do: today |> Date.add(45) |> day_start()),
        custom_values: %{"#{@serviced}" => today |> Date.add(-30 * n) |> Date.to_iso8601()}
      }

      item_row(item, holder)
    end
  end

  defp item_row(item, holder) do
    links = if holder, do: [member_id: {:member, holder}], else: []
    {:equipment_item, item.d4h_equipment_id, with_costs(item), links}
  end

  defp with_costs(item) do
    {km, hour, use} = Map.get(@costs, item.d4h_equipment_id, {nil, nil, nil})
    %{item | cost_per_km_cents: km, cost_per_hour_cents: hour, cost_per_use_cents: use}
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

  # ---- What a demo shows off --------------------------------------------------------

  # Callout takes everyone with GSAR who is active, so Dana, away, comes off it.
  # Swiftwater team takes current swiftwater tickets, so Priya, expired, comes off it.
  @group_rules [
    {9_500_001, "Ground search and rescue"},
    {9_500_003, "Swiftwater"}
  ]

  defp group_rules do
    for {d4h_group_id, endorsement} <- @group_rules do
      in_rule = {d4h_group_id, :in}
      standing_rule = {d4h_group_id, :standing}

      [
        {:group_rule, in_rule, %GroupRule{d4h_group_id: d4h_group_id, kind: :in}, []},
        {:group_rule_reference, {in_rule, endorsement}, %GroupRuleReference{},
         group_rule_id: {:group_rule, in_rule}, endorsement_id: {:endorsement, endorsement}},
        {:group_rule, standing_rule, %GroupRule{d4h_group_id: d4h_group_id, kind: :standing}, []},
        {:group_rule_reference, {standing_rule, :active}, %GroupRuleReference{standing: :active},
         group_rule_id: {:group_rule, standing_rule}}
      ]
    end
    |> List.flatten()
  end

  # Text, link, important, days ago posted, and days on until it comes down.
  @notes [
    {"Pager test Sunday at 10:00. Reply to the page so we know yours works.", nil, true, 1, 6},
    {"Winter tires go on Truck 1 on Saturday. Sign up for a shift at the hall.",
     "https://example.com/tires", false, 3, 10},
    {"Dues are due by the end of the month. Pay at the hall or online.",
     "https://example.com/dues", false, 8, 20}
  ]

  defp whiteboard_notes(now) do
    for {{text, url, important, posted, stays}, n} <- Enum.with_index(@notes, 1) do
      note = %WhiteboardNote{
        d4h_whiteboard_note_id: 9_900_000 + n,
        text: text,
        url: url,
        important: important,
        archived_at: DateTime.add(now, stays, :day),
        d4h_created_at: DateTime.add(now, -posted, :day)
      }

      {:whiteboard_note, 9_900_000 + n, note, []}
    end
  end

  # The places a team admin picks from when they make an activity (#614). A leading !
  # sorts the hall first, as teams do in D4H.
  @bookmarks [
    {"!Hall", "100 Example Road", "49.25000,-123.10000"},
    {"Cedar Creek training ground", nil, "49.37000,-123.02000"},
    {"Ridge trailhead", nil, "49.38000,-123.08000"}
  ]

  defp location_bookmarks do
    for {{title, address, coordinate}, n} <- Enum.with_index(@bookmarks, 1) do
      bookmark = %LocationBookmark{
        d4h_location_bookmark_id: 9_910_000 + n,
        title: title,
        address: address,
        coordinate: coordinate
      }

      {:location_bookmark, title, bookmark, []}
    end
  end

  # Title, kind, its details, and the tags, groups, and equipment it brings.
  @templates [
    {"Weekly training", "exercise",
     %{
       start_time: ~T[19:00:00],
       duration_minutes: 150,
       enough_at: 8,
       place: "Hall training yard",
       coordinate: "49.33000,-122.86000",
       description: "Weekly training."
     }, ["Training"], [9_500_001], []},
    {"Callout", "incident", %{description: "Called out by the police."}, [], [9_500_001],
     [{9_800_001, 0}, {9_800_002, 0}]},
    {"Public education booth", "event",
     %{
       start_time: ~T[10:00:00],
       duration_minutes: 240,
       enough_at: 4,
       full_at: 6,
       place: "Coast Range SAR hall, 100 Example Road",
       coordinate: "49.25000,-123.10000",
       hours: "secondary",
       description: "A booth for the public."
     }, ["Public education"], [9_500_004], [{9_800_008, 0}]}
  ]

  defp templates do
    for {title, kind, details, tags, groups, items} <- @templates do
      template =
        struct!(
          %Template{title: title, activity_kind: kind, custom_values: template_values(title)},
          details
        )

      [
        {:template, title, template, []},
        template_tags(title, tags),
        template_groups(title, groups),
        template_items(title, items)
      ]
    end
    |> List.flatten()
  end

  # Callout fills the fields every callout has the same, so a demo's template shows them.
  defp template_values("Callout") do
    [{"Agency", "Police"}, {"Response Type", "Call-Out"}, {"Region", "South West"}]
    |> organization_values()
    |> Map.put("#{@agency}", [agency_option("Police")])
  end

  defp template_values(_title), do: %{}

  defp template_tags(title, tags) do
    for tag <- tags,
        do:
          {:template_tag, {title, tag}, %TemplateTag{},
           template_id: {:template, title}, tag_id: {:tag, tag}}
  end

  defp template_groups(title, groups) do
    for group <- groups,
        do:
          {:template_group, {title, group}, %TemplateGroup{},
           template_id: {:template, title}, group_id: {:group, group}}
  end

  defp template_items(title, items) do
    for {item, minutes} <- items,
        do:
          {:template_item, {title, item}, %TemplateItem{minutes: minutes},
           template_id: {:template, title}, equipment_item_id: {:equipment_item, item}}
  end

  # Made-up homes on land around the base, one per member with an address, in the cast's
  # order. The last is up the highway in Squamish, for a long drive.
  @homes [
    {49.32000, -123.07000},
    {49.34000, -123.04000},
    {49.25000, -123.00000},
    {49.28400, -122.79300},
    {49.28300, -122.83000},
    {49.20600, -122.91100},
    {49.26000, -123.07000},
    {49.26800, -123.15500},
    {49.32900, -123.16000},
    {49.17000, -123.14000},
    {49.19000, -122.85000},
    {49.21900, -122.60000},
    {49.22100, -122.68900},
    {49.32900, -122.95000},
    {49.23000, -122.97000},
    {49.24100, -122.89000},
    {49.26200, -122.78100},
    {49.70160, -123.15580}
  ]

  # Each member with an address's home, as the mileage report's "lat,lng" point.
  defp homes(people) do
    with_address =
      for {key, _, _, _, _, marks} <- people,
          :not_a_person not in marks and :no_address not in marks,
          do: key

    with_address
    |> Enum.zip(@homes)
    |> Map.new(fn {key, {lat, lng}} -> {key, point(lat, lng)} end)
  end

  defp point(coordinate), do: coordinate |> Coordinate.build() |> Coordinate.to_string(5)
  defp point(lat, lng), do: lat |> Coordinate.build(lng) |> Coordinate.to_string(5)

  defp yard, do: point(@yard_lat, @yard_lng)

  defp home_coordinates(people, homes) do
    for {key, ref_id, _, _, _, _} <- people, home = homes[key] do
      row = %HomeCoordinate{address: "#{ref_id} Example Road", coordinate: home}
      {:home_coordinate, key, row, member_id: {:member, key}}
    end
  end

  # One way by car from each incident's place and the yard to each home, and from the
  # yard to each incident: the pairs the mileage report asks for, saved.
  defp route_distances(homes) do
    places = Enum.map(@incident_places, &point/1)

    pairs =
      for(from <- [yard() | places], home <- Map.values(homes), do: {from, home}) ++
        for place <- places, do: {yard(), place}

    pairs |> Enum.uniq() |> Enum.map(&route_distance/1)
  end

  defp route_distance({from, to} = pair) do
    route = %RouteDistance{origin: from, destination: to, metres: metres(from, to)}
    {:route_distance, pair, route, []}
  end

  # As the crow flies, near enough over a few km, and 40% more for the road.
  @km_per_degree 111.2

  defp metres(from, to) do
    {lat1, lng1} = Coordinate.build(from)
    {lat2, lng2} = Coordinate.build(to)
    across = (lng2 - lng1) * :math.cos((lat1 + lat2) / 2 * :math.pi() / 180)
    km = :math.sqrt((lat2 - lat1) ** 2 + across ** 2) * @km_per_degree
    round(km * 1000 * 1.4)
  end

  # Round trip, in whole km, as App.Operation.BuildMileageReport works it out.
  defp round_trip_km(from, to), do: round(metres(from, to) / 1000 * 2)

  # Travel on the two draft incidents. Missing hiker is part way: a team admin set most
  # rows, some members confirmed, the visitor hasn't, and some rows aren't set. Overdue
  # kayakers is done: every row set and confirmed.
  defp trips(activities, attendances, homes, now) do
    for title <- ["Missing hiker", "Overdue kayakers"],
        activity = Enum.find(activities, &(&1.title == title)),
        {attendance, j} <-
          attendances |> Enum.filter(&attended_on?(&1, activity)) |> Enum.with_index(),
        trip = trip(activity, attendance, j, homes, now),
        do: trip
  end

  defp trip(activity, {:attendance, {_id, key}, row, _links}, j, homes, now) do
    case trip_plan(activity.title, key, j) do
      {nil, _checked?} ->
        nil

      {travel, checked?} ->
        {travel, km} = travel_km(travel, point(activity.coordinate), homes[key])
        checked_days = if activity.title == "Missing hiker", do: 1, else: 8

        trip = %Trip{
          d4h_attendance_id: row.d4h_attendance_id,
          travel: travel,
          km: km,
          checked_at: if(checked?, do: DateTime.add(now, -checked_days, :day))
        }

        {:trip, row.d4h_attendance_id, trip,
         activity_id: {:activity, activity.d4h_activity_id}, member_id: {:member, key}}
    end
  end

  # With no home to drive from, a team admin types the km.
  defp travel_km(travel, place, home) do
    case trip_km(travel, place, home) do
      nil -> {"other", 40}
      km -> {travel, km}
    end
  end

  defp attended_on?({:attendance, {id, _key}, row, _links}, activity),
    do: id == activity.d4h_activity_id and row.status == "attending"

  # How each attended row got there, and whether its member confirmed: nil for not set.
  defp trip_plan("Missing hiker", :visitor, _j), do: {"icp", false}
  defp trip_plan("Missing hiker", "Alex Chen", _j), do: {"icp", true}

  defp trip_plan("Missing hiker", _key, j) do
    case rem(j, 4) do
      0 -> {"icp", true}
      1 -> {"passenger", true}
      2 -> {nil, false}
      3 -> {"yard", false}
    end
  end

  defp trip_plan("Overdue kayakers", _key, j),
    do: if(rem(j, 5) == 2, do: {"passenger", true}, else: {"icp", true})

  defp trip_km("passenger", _place, _home), do: 0
  defp trip_km(_travel, _place, nil), do: nil
  defp trip_km("icp", place, home), do: round_trip_km(place, home)
  defp trip_km("yard", _place, home), do: round_trip_km(yard(), home)
end
