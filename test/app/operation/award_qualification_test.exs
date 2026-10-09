defmodule App.Operation.AwardQualificationTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.Qualification
  alias App.Operation.AwardQualification
  alias App.ViewModel.AwardFormViewModel

  @member %Member{id: 7, d4h_member_id: 70}
  @qualification %Qualification{d4h_qualification_id: 40, title: "First Aid"}

  test "an award runs from midnight on its first day, on the team's clock" do
    values = %AwardFormViewModel{starts_on: ~D[2026-05-01], ends_on: ~D[2029-05-01]}
    row = AwardQualification.plan(@member, @qualification, values, "America/Halifax")

    assert row.action == :award_qualification
    assert row.member_id == 7

    assert row.new_value == %{
             "title" => "First Aid",
             "d4h_qualification_id" => 40,
             "d4h_member_id" => 70,
             "starts_at" => "2026-05-01T03:00:00Z",
             "ends_at" => "2029-05-01T03:00:00Z"
           }
  end

  test "an award with no end never expires" do
    values = %AwardFormViewModel{starts_on: ~D[2026-05-01]}
    row = AwardQualification.plan(@member, @qualification, values, "America/Halifax")
    assert row.new_value["ends_at"] == nil
  end
end
