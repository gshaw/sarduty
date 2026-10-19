defmodule App.ViewModel.MemberFilterViewModelTest do
  use ExUnit.Case, async: true

  alias App.ViewModel.MemberFilterViewModel

  @now ~U[2026-10-18 20:30:15.123456Z]

  test "a rolling period ends now and reaches back that many days" do
    assert MemberFilterViewModel.period_bounds("90d", "America/Vancouver", @now) ==
             {~N[2026-07-20 20:30:15], ~N[2026-10-18 20:30:15]}
  end

  test "a year is the calendar year in the team's time zone" do
    assert MemberFilterViewModel.period_bounds("2026", "America/Vancouver", @now) ==
             {~N[2026-01-01 08:00:00], ~N[2027-01-01 07:00:00]}
  end

  test "the Period filter takes years and the rolling periods it offers" do
    for period <- ~w(all 2026 30d 60d 90d 180d 365d),
        do: assert({:ok, _, _} = MemberFilterViewModel.validate(%{"when" => period}))

    for period <- ~w(7d 90 d last-year),
        do: assert({:error, _} = MemberFilterViewModel.validate(%{"when" => period}))
  end
end
