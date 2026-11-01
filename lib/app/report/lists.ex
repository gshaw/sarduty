defmodule App.Report.Lists do
  @moduledoc """
  The app's lists that a report draws (#784): the rows, the tiles, the search, the
  filters, the sorts, and the pages. The page keeps its own cells and buttons. A list is
  not on the Reports page; Save as report copies its text with the picks as values.

  Each is `%{slug, name, query}`. A filter's name is the URL param the page has always
  used, so Home's links, such as `status=draft&when=recent`, and bookmarks still open
  the same list.
  """

  @lists [
    %{
      slug: "activities",
      name: "Activities",
      query: """
      select title, started_at, duration
      from activities
      order by started_at desc
      search title, ref_id, tracking_number, tags, description
      switch activity 'Kind'
        option incident 'Incidents' where kind = 'incident' and chore = false
        option exercise 'Exercises' where kind = 'exercise' and chore = false
        option event 'Events' where kind = 'event' and chore = false
        option chores 'Chores' where chore = true
      filter when 'When'
        option current 'Current' where current = true sort date
        option recent 'Last 30 days' where recent = true sort date desc
        option past 'Past' where started_at <= NOW sort date desc
        option future 'Future' where started_at >= NOW sort date
        each year(started_at) where year(started_at) = :when
      filter status 'Status'
        option draft 'Draft' where published = false
        option published 'Published' where published = true
      filter hours 'Hours tag'
        option untagged 'No hours tag' where hours_tag_count = 0
        option two 'Two hours tags' where hours_tag_count >= 2
      filter fields 'Required fields'
        option missing 'Missing' where missing_required_fields = true
      sort id 'Activity' ref_id
      sort date 'Date' started_at
      sort hours 'Duration' duration desc
      page 50
      """
    },
    %{
      slug: "members",
      name: "Members",
      query: """
      select name, ref_id, position, last_attended,
        activity_count(:when, :activity_tag), attended_minutes(:when, :activity_tag),
        joined_at, left_at
      from members
      where on_team(:when) and in_group(:group)
      order by name
      search name, position, ref_id
      switch standing 'Standing' default current
        option current 'Not retired' where current = true
        option active 'Active' where standing = 'active'
        option away 'Away' where standing = 'away'
        option retiring 'Retiring' where standing = 'retiring'
        option retired 'Retired' where standing = 'retired'
        option not_a_person 'Not a person' where standing = 'not_a_person'
      filter when 'Period' default THIS_YEAR
      filter group 'Group'
      filter activity_tag 'Tag' more
      filter details 'Details' more
        option missing 'Missing' where details_missing = true
      filter attended 'Attended' more
        option 30 'Not in 30 days' where not_seen(30) = true
        option 60 'Not in 60 days' where not_seen(60) = true
        option 90 'Not in 90 days' where not_seen(90) = true
        option 180 'Not in 180 days' where not_seen(180) = true
        option 365 'Not in a year' where not_seen(365) = true
      filter items 'Items' more
        option held 'Holds some' where holds_items = true
        option none 'Holds none' where holds_items = false
      filter access 'Access' more
        option some 'Can log in' where can_log_in = true
        option none 'No access' where no_access = true
      sort id 'ID' ref_id nulls last
      sort name 'Member' name
      sort role 'Role' position nulls last
      sort attended 'Last attended' last_attended, name
      sort activities 'Activities' activity_count(:when, :activity_tag), name
      sort duration 'Hours' attended_minutes(:when, :activity_tag)
      sort date 'Joined' joined_at
      sort retired 'Retired' left_at nulls last
      page 50
      """
    }
  ]

  @doc "The list with `slug`, or nil."
  def get(slug), do: Enum.find(@lists, &(&1.slug == slug))

  @doc "The Activities list."
  def activities, do: get("activities")

  @doc """
  The Members list. Period and Tag feed the Activities and Hours columns as well as the
  rows. A member opens it with `team_admin?: false`, so team admins' own filters (Details,
  Attended, Items, and Access) and the Away tile drop out (decision 4 of #784).
  """
  def members, do: get("members")
end
