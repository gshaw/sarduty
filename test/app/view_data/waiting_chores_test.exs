defmodule App.ViewData.WaitingChoresTest do
  use ExUnit.Case, async: true

  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.Member
  alias App.ViewData.WaitingChores

  @hall %ChoreCategory{id: 1, title: "Hall and gear"}
  @admin %ChoreCategory{id: 2, title: "Admin"}

  defp chore(id, name, attrs) do
    struct!(
      %Chore{
        id: id,
        member: %Member{id: id, name: name},
        member_id: id,
        date: ~D[2026-11-17],
        minutes: 180,
        description: "Gear day",
        chore_category_id: @hall.id,
        chore_category: @hall
      },
      attrs
    )
  end

  test "chores logged together are one row, A to Z, with the minutes each and the total" do
    g = %{logged_together_id: "g"}

    rows =
      WaitingChores.rows([
        chore(3, "Riley Okafor", g),
        chore(1, "alex Chen", g),
        chore(2, "Cameron Diaz", g)
      ])

    assert [row] = rows
    assert Enum.map(row.chores, & &1.member.name) == ["alex Chen", "Cameron Diaz", "Riley Okafor"]
    assert %{id: 1, ids: [1, 2, 3], minutes: 540, minutes_each: 180, differs: []} = row
  end

  test "a chore logged alone is its own row, oldest first" do
    rows =
      WaitingChores.rows([
        chore(5, "Sam Rivera", %{date: ~D[2026-11-20]}),
        chore(1, "Alex Chen", %{logged_together_id: "g", date: ~D[2026-11-18]}),
        chore(2, "Cameron Diaz", %{logged_together_id: "g", date: ~D[2026-11-18]}),
        chore(4, "Blake Ground", %{date: ~D[2026-11-01]})
      ])

    assert Enum.map(rows, & &1.ids) == [[4], [1, 2], [5]]
    assert [%{minutes_each: nil, minutes: 180} | _rest] = rows
  end

  test "a chore changed on its page stays in its row, and says what differs" do
    g = %{logged_together_id: "g"}

    [row] =
      WaitingChores.rows([
        chore(1, "Alex Chen", g),
        chore(2, "Riley Okafor", Map.put(g, :minutes, 120)),
        chore(
          3,
          "Sam Rivera",
          Map.merge(g, %{
            date: ~D[2026-11-16],
            chore_category_id: 2,
            chore_category: @admin,
            description: "Grant report"
          })
        )
      ])

    assert row.minutes == 480
    assert row.minutes_each == nil

    assert row.differs == [
             "Riley Okafor: 2 hours",
             "Sam Rivera: Nov 16, 2026, Admin, Grant report"
           ]
  end
end
