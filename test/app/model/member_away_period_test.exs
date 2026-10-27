defmodule App.Model.MemberAwayPeriodTest do
  use ExUnit.Case, async: true

  alias App.Model.MemberAwayPeriod

  @today ~D[2026-10-18]
  @now ~U[2026-10-18 18:00:00Z]

  defp period(starts_on, ends_on), do: %MemberAwayPeriod{starts_on: starts_on, ends_on: ends_on}

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
