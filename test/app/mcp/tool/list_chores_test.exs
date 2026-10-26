defmodule App.MCP.Tool.ListChoresTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.ListChores
  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent

  defp chore(id, date, status, event \\ nil) do
    %Chore{
      id: id,
      member_id: 5,
      member: %{name: "Sam"},
      chore_category_id: 3,
      chore_category: %ChoreCategory{title: "Office admin", hours: :primary},
      date: date,
      minutes: 90,
      description: "Sorted the radio cupboard",
      decline_reason: "Already counted",
      status: status,
      chore_event: event
    }
  end

  test "lists oldest first, with what they did and its chore activity once sent" do
    event = %ChoreEvent{d4h_activity_id: 900}

    [first, second] =
      ListChores.build(
        [chore(2, ~D[2026-10-12], :accepted, event), chore(1, ~D[2026-10-03], :declined)],
        %{900 => 44}
      )

    assert first["id"] == 1
    assert first["status"] == "declined"
    assert first["activity_id"] == nil
    assert second["activity_id"] == 44
    assert second["hours"] == "primary"
    assert second["what_they_did"] == "Sorted the radio cupboard"
    refute inspect([first, second]) =~ "Already counted"
  end
end
