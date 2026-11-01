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
end
