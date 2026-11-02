defmodule App.Report.BuiltIn do
  @moduledoc """
  The reports that come with SAR Duty (#768). They live in code and change with the app:
  a team admin runs one, and copies it to change it.

  Each is `%{slug, name, about, query}`, and `teams: :d4h` for one that reads what only a
  D4H team has, such as required fields. A test runs every one, so a field that goes
  fails the build rather than a team admin's report.
  """

  alias App.Adapter.D4H

  @reports [
    %{
      slug: "hours-by-member",
      name: "Hours by member",
      about:
        "Each member's attended hours in a year, by kind of activity. Tax credit letters count hours their own way.",
      query: """
      select member, sum(hours)
      from attendance
      where status = 'Attended' and year(activity.started_at) = :year
        and member.counted = true
      group by member
      pivot activity.kind
      order by member.name
      totals
      search member.name
      filter year 'Year' required
        each year(activity.started_at)
      """
    },
    %{
      slug: "activities-with-two-hours-tags",
      name: "Activities with two hours tags",
      about: "Tax credit letters count one of the tags and say nothing about the other.",
      query: """
      select title, started_at, tags
      from activities
      where hours_tag_count > 1 and year(started_at) = :year
      order by started_at desc
      search title, tags
      filter year 'Year' required
        each year(started_at)
      sort title 'Activity' title
      sort started 'Started' started_at
      """
    },
    %{
      slug: "activities-with-no-hours-tag",
      name: "Activities with no hours tag",
      about: "Published activities that tax credit letters count no hours for.",
      query: """
      select title, started_at
      from activities
      where hours_tag_count = 0 and published = true and year(started_at) = :year
      order by started_at desc
      search title
      filter year 'Year' required
        each year(started_at)
      sort title 'Activity' title
      sort started 'Started' started_at
      """
    },
    %{
      slug: "activities-missing-required-fields",
      name: "Activities missing required fields",
      about: "Draft incidents with a required field left empty, newest first.",
      teams: :d4h,
      query: """
      select title, started_at
      from activities
      where missing_required_fields = true and started_at <= NOW
      order by started_at desc
      search title
      sort title 'Activity' title
      sort started 'Started' started_at
      """
    },
    # Experiment (charts): the Dashboard's charts as built-in reports, each ending in a
    # chart line. Activities by month covers the last 12 months, the Dashboard's, or a year.
    %{
      slug: "activities-by-month",
      name: "Activities by month",
      about: "Incidents, exercises, and events in each month: the last 12 months, or a year.",
      query: """
      select year(started_at), month(started_at), count(id)
      from activities
      where started_at <= NOW
      group by year(started_at), month(started_at)
      pivot kind
      order by year(started_at), month(started_at)
      totals
      filter when 'When' required
        option last12 'The last 12 months' where months_since(started_at) < 12
        each year(started_at) where year(started_at) = :when
      chart columns
      """
    },
    %{
      slug: "activities-this-year",
      name: "Activities this year",
      about: "Activities so far this year, by month, against the same days last year.",
      query: """
      select month(started_at), count(id)
      from activities
      where started_at = THIS_YEAR and started_at <= NOW
      group by month(started_at)
      order by month(started_at)
      label count(id) 'Activities'
      chart stat compare year
      """
    },
    %{
      slug: "incidents-this-year",
      name: "Incidents this year",
      about: "Incidents so far this year, by month, against the same days last year.",
      query: """
      select month(started_at), count(id)
      from activities
      where kind = 'Incident' and started_at = THIS_YEAR and started_at <= NOW
      group by month(started_at)
      order by month(started_at)
      label count(id) 'Incidents'
      chart stat compare year
      """
    },
    %{
      slug: "member-hours-this-year",
      name: "Member hours this year",
      about:
        "Hours members attended so far this year, by month, against the same days last year. Tax credit letters count hours their own way.",
      query: """
      select month(activity.started_at), sum(hours)
      from attendance
      where status = 'Attended' and activity.started_at = THIS_YEAR
        and activity.started_at <= NOW
      group by month(activity.started_at)
      order by month(activity.started_at)
      label sum(hours) 'Member hours'
      chart stat compare year
      """
    },
    %{
      slug: "member-hours-by-month",
      name: "Member hours by month",
      about: "Hours members attended in each of the last 12 months.",
      query: """
      select year(activity.started_at), month(activity.started_at), sum(hours)
      from attendance
      where status = 'Attended' and months_since(activity.started_at) < 12
      group by year(activity.started_at), month(activity.started_at)
      order by year(activity.started_at), month(activity.started_at)
      label sum(hours) 'Member hours'
      chart lines
      """
    },
    %{
      slug: "current-members",
      name: "Current members",
      about: "Members on the team now, people only, not retiring, and how many joined this year.",
      query: """
      select count(id), sum(joined_at = THIS_YEAR)
      from members
      where current = true and counted = true
      label count(id) 'Current members', sum(joined_at = THIS_YEAR) 'Joined this year'
      chart stat
      """
    },
    # Experiment (places): the Dashboard's map, over the same 12 months as its columns.
    %{
      slug: "where-the-team-went",
      name: "Where the team went",
      about: "Activities with a place in the last 12 months, near the team's base.",
      query: """
      select title, started_at, kind, place
      from activities
      where place is not null and months_since(started_at) < 12 and started_at <= NOW
      order by started_at desc
      search title
      chart map
      """
    },
    %{
      slug: "every-day-out",
      name: "Every day out",
      about: "How many activities started on each day of the last 365.",
      query: """
      select date(started_at), count(id)
      from activities
      where started_at = LAST_N_DAYS:364 and started_at <= NOW
      group by date(started_at)
      order by date(started_at) desc
      label count(id) 'Activities'
      chart calendar
      """
    },
    %{
      slug: "when-incidents-start",
      name: "When incidents start",
      about: "Incidents in the last 3 years, by day of the week and hour.",
      query: """
      select day_of_week(started_at), hour(started_at), count(id)
      from activities
      where kind = 'Incident' and started_at = LAST_N_DAYS:1095
      group by day_of_week(started_at), hour(started_at)
      order by count(id) desc
      label count(id) 'Incidents'
      chart week
      """
    },
    %{
      slug: "busiest-incidents",
      name: "Busiest incidents",
      about: "The 10 incidents with the most hours since the day you pick.",
      query: """
      select title, started_at, attended_count, attended_hours
      from activities
      where kind = 'Incident' and started_at >= :since
      order by attended_hours desc
      limit 10
      """
    },
    %{
      slug: "replies-by-member",
      name: "Replies by member",
      about: "How each active member answered in the last 365 days.",
      query: """
      select member, count(id)
      from attendance
      where activity.started_at = LAST_N_DAYS:365 and member.standing = 'Active'
      group by member
      pivot status
      order by member.name
      search member.name
      """
    },
    %{
      slug: "most-incidents-attended",
      name: "Most incidents attended",
      about: "The 15 members who attended the most incidents last year.",
      query: """
      select member, count(id), sum(hours)
      from attendance
      where status = 'Attended' and activity.kind = 'Incident'
        and activity.started_at = LAST_YEAR
      group by member
      order by count(id) desc
      limit 15
      label count(id) 'Incidents'
      """
    },
    %{
      slug: "not-attended-in-a-year",
      name: "Not attended in a year",
      about:
        "Members to check in with, counted from the attendance clock as Needs attention counts.",
      query: """
      select name, standing, last_attended
      from members
      where counted = true and not_seen(365)
      order by last_attended
      search name
      sort name 'Member' name
      sort attended 'Last attended' last_attended
      """
    },
    %{
      slug: "members-without-a-qualification",
      name: "Members without a qualification",
      about: "Active members who do not hold the qualification you pick.",
      query: """
      select name, position, groups
      from members
      where standing = 'Active' and counted = true
        and qualifications excludes (:qualification)
      order by name
      search name, position
      filter qualification 'Qualification' required
        each qualifications
      sort name 'Member' name
      """
    },
    %{
      slug: "new-members",
      name: "New members this year",
      about: "Members who joined this year.",
      query: """
      select name, joined_at, position
      from members
      where joined_at = THIS_YEAR
      order by joined_at
      search name, position
      sort name 'Member' name
      sort joined 'Joined' joined_at
      """
    },
    %{
      slug: "hours-in-a-tag",
      name: "Hours in a tag",
      about:
        "Each member's activities and hours with a tag you pick, such as rope or swiftwater.",
      query: """
      select name, activity_count(:when, :tag), attended_minutes(:when, :tag)
      from members
      where on_team(:when) and counted = true
      order by attended_minutes(:when, :tag) desc, name
      label activity_count(:when, :tag) 'Activities', attended_minutes(:when, :tag) 'Hours'
      search name
      switch standing 'Standing' default current
        option current 'Not retired' where current = true
        option retired 'Retired' where standing = 'retired'
      filter tag 'Tag'
      filter when 'Period' default THIS_YEAR
      sort name 'Member' name
      sort activities 'Activities' activity_count(:when, :tag), name
      sort hours 'Hours' attended_minutes(:when, :tag), name
      """
    },
    %{
      slug: "members-missing-details",
      name: "Members missing details",
      about: "Members with no mobile number, email, or address, and which they're missing.",
      query: """
      select name, position, missing_details
      from members
      where details_missing = true
      order by name
      search name, position
      sort name 'Member' name
      """
    },
    %{
      slug: "members-holding-items",
      name: "Members holding items",
      about: "Who holds the team's items, and, for retiring members, who holds none.",
      query: """
      select name, position, standing
      from members
      where counted = true
      order by name
      search name, position
      switch standing 'Standing' default current
        option current 'Not retired' where current = true
        option retiring 'Retiring' where standing = 'retiring'
        option retired 'Retired' where standing = 'retired'
      filter items 'Items' default held
        option held 'Holds some' where holds_items = true
        option none 'Holds none' where holds_items = false
      sort name 'Member' name
      """
    },
    %{
      slug: "members-who-can-log-in",
      name: "Members who can log in",
      about: "Who can log in to the team's records, and who has no access.",
      query: """
      select name, position, standing
      from members
      where counted = true
      order by name
      search name, position
      switch standing 'Standing' default current
        option current 'Not retired' where current = true
        option retiring 'Retiring' where standing = 'retiring'
        option retired 'Retired' where standing = 'retired'
      filter access 'Access' default some
        option some 'Can log in' where can_log_in = true
        option none 'No access' where no_access = true
      sort name 'Member' name
      """
    },
    %{
      slug: "members-by-standing",
      name: "Members by standing",
      about: "How many members are active, away, retiring, and retired.",
      query: """
      select standing, count(id)
      from members
      group by standing
      order by count(id) desc
      label count(id) 'Members'
      """
    },
    %{
      slug: "awards-expiring",
      name: "Awards expiring in 60 days",
      about: "Renewals to record soon.",
      query: """
      select member, qualification, ends_at
      from awards
      where ends_at = NEXT_N_DAYS:60 and member.counted = true
        and member.standing != 'Retired'
      order by ends_at
      search member.name, qualification.title
      sort member 'Member' member.name
      sort expires 'Expires' ends_at
      """
    },
    %{
      slug: "qualification-coverage",
      name: "Qualification coverage",
      about: "How many active members hold each qualification.",
      query: """
      select qualification, count(distinct member)
      from awards
      where current = true and member.standing = 'Active'
      group by qualification
      order by count(distinct member) desc
      label count(distinct member) 'Active members'
      chart bars
      """
    },
    %{
      slug: "equipment-out-of-service",
      name: "Equipment out of service",
      about: "Lost and unserviceable items, and where they were last.",
      query: """
      select title, kind, location
      from equipment
      where status in ('Unserviceable', 'Lost')
      order by location, title
      search title, kind, location
      switch status 'Status'
        option unserviceable 'Unserviceable' where status = 'Unserviceable'
        option lost 'Lost' where status = 'Lost'
      sort title 'Item' title
      sort location 'Location' location
      """
    },
    %{
      slug: "equipment-held-by-retiring-members",
      name: "Equipment held by retired or retiring members",
      about: "Items to get back.",
      query: """
      select title, kind, holder, holder.standing
      from equipment
      where holder.standing in ('Retired', 'Retiring')
      order by holder.name
      """
    },
    %{
      slug: "equipment-expiring",
      name: "Equipment expiring in 90 days",
      about: "Items to replace or check soon.",
      query: """
      select title, kind, location, expires_at
      from equipment
      where expires_at = NEXT_N_DAYS:90
      order by expires_at
      """
    },
    %{
      slug: "equipment-by-kind",
      name: "Equipment by kind and status",
      about: "How many of each kind of equipment are in service, unserviceable, or lost.",
      query: """
      select kind, count(id)
      from equipment
      where type = 'Equipment'
      group by kind
      pivot status
      order by count(id) desc
      limit 20
      """
    },
    %{
      slug: "vehicle-use",
      name: "Vehicle use",
      about: "The activities and distance for each vehicle in a year.",
      query: """
      select item, count(activity), sum(km)
      from equipment_use
      where item.type = 'Vehicle' and year(activity.started_at) = :year
      group by item
      order by sum(km) desc
      label count(activity) 'Activities'
      filter year 'Year' required
        each year(activity.started_at)
      """
    },
    %{
      slug: "group-sizes",
      name: "Group sizes",
      about: "How many current members are in each group, largest first.",
      query: """
      select title, member_count
      from groups
      order by member_count desc
      search title
      sort title 'Group' title
      sort members 'Members' member_count desc
      """
    }
  ]

  @doc "Every built-in report, in the order Reports lists them."
  def all, do: @reports

  @doc "The built-in reports `team` can run: a Records team has no D4H custom fields."
  def all(team), do: Enum.filter(@reports, &for_team?(&1, team))

  @doc "The built-in report with `slug` that `team` can run, or nil."
  def get(team, slug), do: team |> all() |> Enum.find(&(&1.slug == slug))

  defp for_team?(%{teams: :d4h}, team), do: not D4H.records?(team)
  defp for_team?(_report, _team), do: true

  @doc "The built-in report with `slug`, or nil."
  def get(slug), do: Enum.find(@reports, &(&1.slug == slug))

  @doc """
  How to fix a row, for a report a team admin opens to fix what it lists: where its
  hours tags change, in SAR Duty or in `service`'s own app (D4H.service/1).
  """
  def fix("activities-with-two-hours-tags", :records),
    do: "Take each extra tag off with Change tags."

  def fix("activities-with-two-hours-tags", service),
    do:
      "Take each extra tag off with Change tags, or in #{D4H.service_name(service)} for a published one."

  def fix("activities-with-no-hours-tag", :records),
    do: "Set each one's hours with Change tags."

  def fix("activities-with-no-hours-tag", service),
    do: "Set each one's hours tag in #{D4H.service_name(service)}."

  def fix(_slug, _service), do: nil
end
