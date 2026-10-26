defmodule App.Operation.ProposeChoresTest do
  use ExUnit.Case, async: true

  alias App.Model.ChoreCategory
  alias App.Model.Member
  alias App.Operation.ProposeChores

  @today ~D[2026-11-02]
  @mei %Member{id: 10, name: "Mei Chen"}
  @gone %Member{id: 11, name: "Sam Ortiz", left_at: ~U[2026-06-30 07:00:00Z]}
  @admin %ChoreCategory{id: 3, title: "Office admin", hours: :primary}

  defp context(taken \\ []) do
    %{
      members: %{10 => @mei, 11 => @gone},
      categories: [@admin],
      taken: MapSet.new(taken),
      open_years: [2026]
    }
  end

  defp chore(attrs) do
    Map.merge(
      %{
        "member_id" => 10,
        "chore_category_id" => 3,
        "date" => "2026-10-31",
        "minutes" => 90,
        "description" => "Sorted the radio cupboard"
      },
      attrs
    )
  end

  test "a chore becomes an add_chore row with what it would be" do
    {[row], []} = ProposeChores.plan(context(), [chore(%{"reason" => "Row 2"})], @today)

    assert row.action == :add_chore
    assert row.member_id == 10
    assert row.reason == "Row 2"

    assert row.new_value == %{
             "chore_category_id" => 3,
             "category" => "Office admin",
             "date" => "2026-10-31",
             "minutes" => 90,
             "description" => "Sorted the radio cupboard",
             "check" => nil
           }
  end

  test "a chore matching one logged already is proposed with a check" do
    taken = context([{10, 3, ~D[2026-10-31], 90}])
    {[row], []} = ProposeChores.plan(taken, [chore(%{})], @today)

    assert row.new_value["check"] ==
             "Mei Chen already has 1h 30m of Office admin on Oct 31, 2026."
  end

  test "chores that cannot be added come back as problems" do
    {[], problems} =
      ProposeChores.plan(
        context(),
        [
          chore(%{"member_id" => 99}),
          chore(%{"chore_category_id" => 7}),
          chore(%{"date" => "2026-11-05"}),
          chore(%{"date" => "2025-12-31"}),
          chore(%{"member_id" => 11}),
          chore(%{"minutes" => 2000}),
          chore(%{"description" => " "})
        ],
        @today
      )

    assert problems == [
             "No member 99 on this team.",
             "No open chore category 7 on this team.",
             "2026-11-05 is in the future. Give a date that has passed.",
             "2025-12-31 is not in an open year. Give a date in 2026.",
             "Sam Ortiz left the team before 2026-10-31.",
             "Give minutes from 1 to 1440, not 2000.",
             "Give what they did for each chore."
           ]
  end
end
