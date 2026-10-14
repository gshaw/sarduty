defmodule App.ViewData.EndorsementRowsTest do
  use ExUnit.Case, async: true

  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification
  alias App.ViewData.EndorsementRows

  defp endorsement(id, name, ids, on_card \\ false) do
    %Endorsement{
      id: id,
      name: name,
      on_card: on_card,
      endorsement_qualifications:
        Enum.map(ids, &%EndorsementQualification{d4h_qualification_id: &1})
    }
  end

  @titles %{1 => "OFA 1", 2 => "OFA 3", 3 => "PSLV"}

  test "a stricter on-card endorsement stands in for the one it implies" do
    rows =
      EndorsementRows.rows(
        [endorsement(1, "First Aid 7", [1, 2], true), endorsement(2, "First Aid 70", [2], true)],
        %{},
        @titles,
        [{10, 2}]
      )

    assert [%{hidden_by: [%{name: "First Aid 70"}]}, %{hidden_by: []}] = rows
  end

  test "same qualifications, a deleted one, and nobody holding one are problems" do
    rows =
      EndorsementRows.rows(
        [
          endorsement(1, "PSLV", [3]),
          endorsement(2, "PSLV Registration", [3]),
          endorsement(3, "Rope", [99])
        ],
        %{},
        @titles,
        [{10, 3}]
      )

    assert [%{same_as: [%{id: 2}]}, %{same_as: [%{id: 1}]}, %{missing: 1, members: 0}] = rows
    assert Enum.all?(rows, &EndorsementRows.problem?/1)
  end

  test "an include lists by name and counts toward members and cards" do
    seven = %{endorsement(1, "First Aid 7", [1], true) | included_ids: [2], earned_by_ids: [1, 2]}
    seventy = endorsement(2, "First Aid 70", [2], true)

    [seven_row, seventy_row] = EndorsementRows.rows([seven, seventy], %{}, @titles, [{10, 2}])

    assert %{qualifications: ["OFA 1"], includes: [%{id: 2, name: "First Aid 70"}]} = seven_row
    assert seven_row.members == 1
    assert seven_row.hidden_by == [%{id: 2, name: "First Aid 70"}]
    assert seventy_row.includes == []
  end
end
