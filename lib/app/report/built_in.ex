defmodule App.Report.BuiltIn do
  @moduledoc """
  The reports that come with SAR Duty (#768). They live in code and change with the app:
  a team admin runs one, and copies it to change it.

  Each is `%{slug, name, about, query}`. A test runs every one, so a field that goes
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
      """
    },
    %{
      slug: "activities-with-two-hours-tags",
      name: "Activities with two hours tags",
      about: "Tax credit letters count one of the tags and say nothing about the other.",
      query: """
      select ref_id, title, started_at, tags
      from activities
      where hours_tag_count > 1 and year(started_at) = :year
      order by started_at desc
      """
    },
    %{
      slug: "activities-with-no-hours-tag",
      name: "Activities with no hours tag",
      about: "Published activities that tax credit letters count no hours for.",
      query: """
      select ref_id, title, started_at
      from activities
      where hours_tag_count = 0 and published = true and year(started_at) = :year
      order by started_at desc
      """
    },
    %{
      slug: "activities-by-month",
      name: "Activities by month",
      about: "Incidents, exercises, and events in each month of a year.",
      query: """
      select month(started_at), count(id)
      from activities
      where year(started_at) = :year
      group by month(started_at)
      pivot kind
      totals
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
      """
    }
  ]

  @doc "Every built-in report, in the order Reports lists them."
  def all, do: @reports

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
