defmodule App.Model.MemberAwayPeriodTest do
  use ExUnit.Case, async: true

  alias App.Model.MemberAwayPeriod

  @today ~D[2026-10-18]

  defp period(starts_on, ends_on), do: %MemberAwayPeriod{starts_on: starts_on, ends_on: ends_on}

  test "a member with no current away period is active" do
    past = period(~D[2026-01-01], ~D[2026-03-01])
    upcoming = period(~D[2026-11-01], ~D[2026-12-01])
    assert MemberAwayPeriod.standing(%{not_a_person: false}, [past, upcoming], @today) == :active
  end

  test "the first and last days are both away" do
    for p <- [period(@today, ~D[2026-11-01]), period(~D[2026-10-01], @today)],
        do: assert({:away, ^p} = MemberAwayPeriod.standing(%{not_a_person: false}, [p], @today))
  end

  test "of overlapping away periods, the one that ends last decides" do
    short = period(~D[2026-10-01], ~D[2026-10-31])
    long = period(~D[2026-09-01], ~D[2027-03-01])

    assert {:away, ^long} =
             MemberAwayPeriod.standing(%{not_a_person: false}, [short, long], @today)
  end

  test "not a person wins over an away period" do
    p = period(~D[2026-10-01], ~D[2026-10-31])
    assert MemberAwayPeriod.standing(%{not_a_person: true}, [p], @today) == :not_a_person
  end

  test "an early end makes yesterday the last day, only for a period already under way" do
    under_way = period(~D[2026-10-01], ~D[2026-12-01])
    assert MemberAwayPeriod.early_end(under_way, @today) == {:ok, ~D[2026-10-17]}

    for p <- [
          period(@today, ~D[2026-12-01]),
          period(~D[2026-11-01], ~D[2026-12-01]),
          period(~D[2026-01-01], ~D[2026-03-01])
        ],
        do: assert(MemberAwayPeriod.early_end(p, @today) == :error)
  end
end
