defmodule App.Model.MemberTest do
  use App.DataCase, async: true

  import App.DataFixtures

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
end
