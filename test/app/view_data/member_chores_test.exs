defmodule App.ViewData.MemberChoresTest do
  use ExUnit.Case, async: true

  alias App.Model.Chore
  alias App.ViewData.MemberChores

  defp chore(id, date, minutes, status),
    do: %Chore{id: id, date: date, minutes: minutes, status: status}

  test "months come newest first, each with its own chores and totals by status" do
    chores = [
      chore(1, ~D[2026-09-03], 240, :declined),
      chore(2, ~D[2026-10-02], 105, :accepted),
      chore(3, ~D[2026-10-28], 60, :waiting),
      chore(4, ~D[2026-10-14], 60, :accepted),
      chore(5, ~D[2026-09-20], 240, :accepted)
    ]

    [october, september] = MemberChores.months(chores)

    assert october.month == ~D[2026-10-01]
    assert Enum.map(october.chores, & &1.id) == [3, 4, 2]
    assert %{accepted: 165, waiting: 60, declined: 0} = october
    assert %{month: ~D[2026-09-01], accepted: 240, declined: 240} = september
  end

  test "the year's numbers count accepted chores done that year, and every waiting one" do
    chores = [
      chore(1, ~D[2025-12-30], 60, :accepted),
      chore(2, ~D[2026-01-04], 90, :accepted),
      chore(3, ~D[2026-02-01], 30, :declined),
      chore(4, ~D[2025-12-31], 45, :waiting),
      chore(5, ~D[2026-03-01], 15, :waiting)
    ]

    assert MemberChores.stats(chores, 2026) == %{
             accepted_minutes: 90,
             accepted_count: 1,
             waiting_minutes: 60
           }
  end
end
