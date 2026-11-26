defmodule App.ViewModel.ChoreFilterViewModelTest do
  use ExUnit.Case, async: true

  alias App.ViewModel.ChoreFilterViewModel

  @tz "America/Vancouver"
  @november ~U[2026-11-25 20:00:00Z]

  defp options(params) do
    {:ok, options, _changeset} = ChoreFilterViewModel.validate(params)
    options
  end

  test "opens on the last 12 months, and takes a month period, a year, or All" do
    assert options(%{}).when == "12mo"
    assert options(%{"when" => "3mo"}).when == "3mo"
    assert options(%{"when" => "2025"}).when == "2025"
    assert options(%{"when" => "all"}).when == "all"
  end

  test "a month is mo: m and a days period are refused" do
    for value <- ~w(3m 90d 2mo),
        do: assert({:error, _} = ChoreFilterViewModel.validate(%{"when" => value}))
  end

  test "the period's dates are whole months or the calendar year" do
    assert ChoreFilterViewModel.dates("12mo", @november, @tz) == {~D[2025-12-01], ~D[2026-11-30]}
    assert ChoreFilterViewModel.dates("2025", @november, @tz) == {~D[2025-01-01], ~D[2025-12-31]}
    assert ChoreFilterViewModel.dates("all", @november, @tz) == nil
  end

  test "Period offers the month periods, each year newest first, then All" do
    assert ChoreFilterViewModel.when_kinds([2026, 2025]) == [
             {"This month", "1mo"},
             {"Last 3 months", "3mo"},
             {"Last 6 months", "6mo"},
             {"Last 12 months", "12mo"},
             {"2026", "2026"},
             {"2025", "2025"},
             {"All", "all"}
           ]
  end

  test "a chore before the last 12 months comes back on its year" do
    assert ChoreFilterViewModel.when_for(~D[2025-10-14], @november, @tz) == "2025"
    assert ChoreFilterViewModel.when_for(~D[2025-12-01], @november, @tz) == nil
    assert ChoreFilterViewModel.when_for(~D[2026-10-14], @november, @tz) == nil
  end

  test "the URL carries Category and Member, and a period only off its default and Waiting" do
    filter = options(%{"category" => "7", "member" => "4", "when" => "2025"})

    assert ChoreFilterViewModel.query_params(:accepted, filter) ==
             [view: :accepted, category: 7, member: 4, when: "2025"]

    assert ChoreFilterViewModel.query_params(:waiting, filter) == [category: 7, member: 4]
    assert ChoreFilterViewModel.query_params(:yours, filter) == [view: :yours]
    assert ChoreFilterViewModel.query_params(:declined, options(%{})) == [view: :declined]
  end
end
