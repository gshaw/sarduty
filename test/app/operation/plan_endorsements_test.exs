defmodule App.Operation.PlanEndorsementsTest do
  use ExUnit.Case, async: true

  alias App.Operation.PlanEndorsements

  @titles %{1 => "OFA 1", 2 => "OFA 3", 3 => "Medical Doctor", 4 => "PSLV", 5 => "Rope"}
  @groups %{10 => "!!! GSAR Callout", 20 => "GSTL", 30 => "One Click"}

  defp clause(id, group, name, ids, on_card \\ false),
    do: %{id: id, d4h_group_id: group, name: name, on_card: on_card, qualification_ids: ids}

  defp plan(clauses), do: PlanEndorsements.plan(clauses, @titles, @groups)

  test "clauses with the same qualifications become one, named for the card, then by use" do
    assert [%{name: "PSLV", d4h_group_ids: [10, 20, 30], qualification_ids: [4]}] =
             plan([
               clause(1, 10, "PSLV", [4]),
               clause(2, 20, "PSLV Registration", [4]),
               clause(3, 30, "PSLV", [4]),
               clause(4, 30, nil, [4])
             ])

    assert [%{name: "Criminal Record Check", on_card: true}] =
             plan([clause(1, 10, "CRC", [4]), clause(2, 20, "Criminal Record Check", [4], true)])
  end

  test "a name with different lists stays on the longest; the others get a name of their own" do
    endorsements =
      plan([
        clause(1, 20, "First Aid", [1, 2], true),
        clause(2, 10, "First Aid", [1, 2, 3], true)
      ])

    assert [
             %{name: "OFA 1 or OFA 3", on_card: false, d4h_group_ids: [20]},
             %{name: "First Aid", on_card: true, d4h_group_ids: [10]}
           ] = endorsements

    long = %{1 => String.duplicate("x", 40), 2 => String.duplicate("y", 40), 3 => "MD"}

    assert [%{name: "First Aid – GSTL"}, %{name: "First Aid"}] =
             PlanEndorsements.plan(
               [clause(1, 20, "First Aid", [1, 2]), clause(2, 10, "First Aid", [1, 2, 3])],
               long,
               @groups
             )
  end

  test "an unnamed clause takes its qualifications' names, or its group's" do
    assert [%{name: "OFA 1 or OFA 3"}] = plan([clause(1, 10, nil, [1, 2])])

    titles = %{1 => String.duplicate("x", 40), 2 => String.duplicate("y", 40)}

    assert [%{name: "GSAR Callout"}] =
             PlanEndorsements.plan([clause(1, 10, nil, [1, 2])], titles, @groups)
  end

  test "empty clauses are dropped, and a made-up name never takes one in use" do
    names =
      [
        clause(1, 10, "Empty", []),
        clause(2, 10, nil, [5]),
        clause(3, 20, "Rope", [5, 1]),
        clause(4, 30, nil, [5, 1, 2]),
        clause(5, 30, nil, [3, 5])
      ]
      |> plan()
      |> Enum.map(& &1.name)

    assert names == ["GSAR Callout", "Rope", "OFA 1 or OFA 3 or Rope", "Medical Doctor or Rope"]
  end
end
