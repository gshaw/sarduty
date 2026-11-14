defmodule App.Model.CustomFieldAnswerCountTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.CustomField

  # CustomField.answer_count/1, which decides whether a field can be deleted (#1056).
  test "counts the kind's records with an answer, and one not copied yet" do
    team = team_fixture()
    other = team_fixture()
    field = custom_field_fixture(team, %{d4h_custom_field_id: 93, target: "incident"})

    activity_fixture(team, %{activity_kind: "incident", custom_values: %{"93" => "Yes"}})
    activity_fixture(team, %{activity_kind: "incident", custom_values: %{"94" => "Other"}})
    # Not copied yet, so it may hold one.
    activity_fixture(team, %{activity_kind: "incident", custom_values: nil})
    # Another kind, a deleted one, and another team's never count.
    activity_fixture(team, %{activity_kind: "exercise", custom_values: %{"93" => "Yes"}})

    activity_fixture(team, %{
      activity_kind: "incident",
      custom_values: %{"93" => "Yes"},
      deleted_at: ~U[2026-11-01 00:00:00Z]
    })

    activity_fixture(other, %{activity_kind: "incident", custom_values: %{"93" => "Yes"}})

    assert CustomField.answer_count(field) == 2
  end

  test "a member's and an item's answers count, and none means it can be deleted" do
    team = team_fixture()
    call_sign = custom_field_fixture(team, %{d4h_custom_field_id: 70, target: "member"})
    serviced = custom_field_fixture(team, %{d4h_custom_field_id: 80, target: "equipment"})

    assert CustomField.answer_count(call_sign) == 0
    assert CustomField.answer_count(serviced) == 0

    member_fixture(team, %{custom_values: %{"70" => "SAR 12"}})
    member_fixture(team, %{custom_values: %{}})
    equipment_item_fixture(team, %{custom_values: %{"80" => "2026-10-01"}})

    assert CustomField.answer_count(call_sign) == 1
    assert CustomField.answer_count(serviced) == 1
  end
end
