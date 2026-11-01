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
      select title, kind, started_at, duration
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
    }
  ]

  @doc "The list with `slug`, or nil."
  def get(slug), do: Enum.find(@lists, &(&1.slug == slug))

  @doc "The Activities list."
  def activities, do: get("activities")
end
