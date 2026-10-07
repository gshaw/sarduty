defmodule App.Model.MemberTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Member

  test "takes whatever D4H holds, however long or odd" do
    # A D4H address field once held a paragraph of notes and broke a team's first refresh.
    member =
      member_fixture(team_fixture(), %{
        name: String.duplicate("n", 80),
        address: String.duplicate("a", 500),
        email: "not an email"
      })

    assert String.length(member.address) == 500
  end

  test "missing details are a photo D4H says it lacks, a mobile phone, and an email" do
    assert Member.missing_details(%{
             has_photo: true,
             phone: "604-555-0100",
             email: "a@example.com"
           }) ==
             []

    assert Member.missing_details(%{has_photo: false, phone: nil, email: ""}) ==
             [:photo, :mobile_phone, :email]

    # Nobody has asked D4H about the photo yet, so it isn't counted as missing.
    assert Member.missing_details(%{
             has_photo: nil,
             phone: "604-555-0100",
             email: "a@example.com"
           }) ==
             []
  end
end
