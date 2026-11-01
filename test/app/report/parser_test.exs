defmodule App.Report.ParserTest do
  use ExUnit.Case, async: true

  alias App.Report.Error
  alias App.Report.Parser
  alias App.Report.Query

  test "reads every clause, in order" do
    {:ok, query} =
      Parser.parse("""
      SELECT member, sum(hours)
      from attendance
      where status = 'Attended' and year(activity.started_at) = :year
        and member.counted = true
      group by member
      pivot activity.kind
      order by member.name desc
      limit 10 offset 5
      label sum(hours) 'Hours'
      totals
      """)

    assert query.from == "attendance"
    assert Enum.map(query.select, &Query.text/1) == ["member", "sum(hours)"]

    assert Query.text(query.where) ==
             "status = 'Attended' and year(activity.started_at) = :year and member.counted = true"

    assert Enum.map(query.group_by, &Query.text/1) == ["member"]
    assert Enum.map(query.pivot, &Query.text/1) == ["activity.kind"]
    assert [{order, :desc}] = query.order_by
    assert Query.text(order) == "member.name"
    assert {query.limit, query.offset} == {10, 5}
    assert [{_sum, "Hours"}] = query.labels
    assert query.totals
  end

  test "reads conditions, dates, ranges, and lists" do
    {:ok, query} =
      Parser.parse("""
      select name from members
      where (last_attended < LAST_N_DAYS:365 or last_attended is null)
        and joined_at >= date '2026-01-01' and not person = false
        and groups includes ('Callout', :group) and qualifications excludes ('First Aid')
        and name not in ('A', 'B') and position starts with 'Team' and name contains 'o'
        and not_seen(365)
      """)

    assert Query.text(query.where) ==
             "(last_attended < LAST_N_DAYS:365 or last_attended is null) and joined_at >= date '2026-01-01' " <>
               "and not person = false and groups includes ('Callout', :group) " <>
               "and qualifications excludes ('First Aid') and name not in ('A', 'B') " <>
               "and position starts with 'Team' and name contains 'o' and not_seen(365)"
  end

  test "count takes distinct, and a quote written twice is one" do
    {:ok, query} =
      Parser.parse(
        "select count(distinct member) from attendance where status = 'Can''t make it'"
      )

    assert Enum.map(query.select, &Query.text/1) == ["count(distinct member)"]
    assert {:op, :eq, _, {:literal, "Can't make it", 1}, 1} = query.where
  end

  test "a comment runs to the end of its line" do
    assert {:ok, %{from: "members"}} =
             Parser.parse("-- Members\nselect name from members -- all\n")
  end

  test "each mistake says how to fix it, on its line" do
    for {text, line, message} <- [
          {"", nil, "Write a query, starting with select."},
          {"from members", 1, "Start the query with select."},
          {"select name", nil, "Add from and a subject after the select, such as from members."},
          {"select * from members", 1, "Name the fields to show: a report cannot select *."},
          {"select name from members\norder by name\nwhere counted = true", 3,
           "Move where before order by, or write it once."},
          {"select name from members where name = 'x", 1,
           "Close the quote: a value starts with ' and has no end."},
          {"select name from members\nwhere joined_at = LAST_N_DAYS", 2,
           "Write a number of days or months after LAST_N_DAYS, such as LAST_N_DAYS:30."},
          {"select name from members limit ten", 1, "Write a whole number after limit."},
          {"select name from members where name ; 'x'", 1, "Remove ;: a query cannot use it."},
          {"select name from members where groups includes 'Callout'", 1,
           "Put the list in brackets: ('Callout', 'Rope')."}
        ] do
      assert Parser.parse(text) == {:error, %Error{line: line, message: message}}, text
    end
  end

  describe "the page's clauses (#784)" do
    test "reads search, a switch, filters with options and each, sorts, and page" do
      {:ok, query} =
        Parser.parse("""
        select title, started_at
        from activities
        order by started_at desc nulls last
        search title, ref_id, tags
        switch activity 'Kind'
          option incident 'Incidents' where kind = 'incident'
          option exercise 'Exercises' where kind = 'exercise'
        filter when 'When' default THIS_YEAR
          option past 'Past' where started_at <= NOW sort date desc
          option future 'Future' where started_at >= NOW sort date
          each year(started_at) where year(started_at) = :when
        filter status 'Status' required more default draft
          option draft 'Draft' where published = false
          option published 'Published' where published = true
        sort date 'Date' started_at
        sort hours 'Hours' attended_hours desc, title
        page 50
        """)

      assert [{_, {:desc, :nulls_last}}] = query.order_by
      assert Enum.map(query.search, &Query.text/1) == ["title", "ref_id", "tags"]

      assert [switch, when_filter, status] = query.filters
      assert %{kind: :switch, name: "activity", label: "Kind", required: false} = switch
      assert Enum.map(switch.options, & &1.value) == ["incident", "exercise"]

      assert %{kind: :filter, default: :this_year, more: false} = when_filter

      assert [%{value: "past", sort: {"date", :desc}}, %{sort: {"date", nil}}] =
               when_filter.options

      assert Query.text(when_filter.each.expr) == "year(started_at)"
      assert Query.text(when_filter.each.where) == "year(started_at) = :when"
      assert Query.text(hd(when_filter.options).where) == "started_at <= NOW"

      assert %{required: true, more: true, default: "draft"} = status
      assert [%{value: "date"}, %{value: "hours", order: [{_, :desc}, {_, :asc}]}] = query.sorts
      assert query.page == 50
    end

    test "a query without them has none" do
      {:ok, query} = Parser.parse("select name from members")
      refute Query.page_clauses?(query)
    end

    test "a sort may be named id: its name is only the sort's value in the URL" do
      {:ok, query} = Parser.parse("select title from activities\nsort id 'ID' ref_id")
      assert [%{value: "id"}] = query.sorts
    end

    defp page_error(text), do: text |> Parser.parse() |> then(fn {:error, e} -> Error.text(e) end)

    test "says what's wrong with them" do
      base = "select title from activities\n"

      assert page_error(base <> "option draft 'Draft'") ==
               "Line 2: Write option under a switch or filter."

      assert page_error(base <> "filter status 'Status'\n  option all 'All'") ==
               "Line 3: Name the option something other than all: All is the menu's own."

      assert page_error(base <> "filter q 'Search'\n  option a 'A'") ==
               "Line 2: Name the filter something other than q: the page uses it."

      assert page_error(base <> "switch status 'Status'") ==
               "Line 2: Write an option under switch status: each is a tile."

      assert page_error(base <> "page 50\nsearch title") == "Line 3: Move search before page."
      assert page_error(base <> "page 0") =~ "Line 2: Write how many rows a page shows"

      assert page_error(base <> "switch a 'A'\n option x 'X'\nswitch b 'B'\n option y 'Y'") ==
               "Line 4: Write one switch: a page has one row of tiles."

      assert page_error(base <> "filter s 'S'\n option x 'X' sort date") ==
               "Line 3: There is no sort date. Add sort date 'Label' and a field."

      assert page_error("select title from activities limit 10\npage 50") ==
               "Take out limit: page shows the rows a page at a time."

      assert page_error(
               "select month(started_at), count(id) from activities group by month(started_at) pivot kind\npage 50"
             ) == "Take out page: a report with pivot shows all its rows."

      assert page_error("select title from activities order by title nulls") ==
               "Line 1: Write nulls first or nulls last."
    end
  end
end
