defmodule App.Model.CustomFieldMemberFieldsTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.CustomField

  # CustomField.member_fields/2, the one home of who sees a member field's values (#1056).
  test "a team admin gets every live member field; a member only what D4H lets them see" do
    team = team_fixture()

    for {title, privacy, restricted} <- [
          {"Call sign", "viewable", false},
          {"Areas", "editable", false},
          {"Year of birth", "editable", true},
          {"Heritage", "viewable", true},
          {"Notes", "hidden", false},
          {"Hidden and restricted", "hidden", true}
        ],
        do:
          custom_field_fixture(team, %{
            target: "member",
            title: title,
            member_privacy: privacy,
            restricted: restricted
          })

    custom_field_fixture(team, %{
      target: "member",
      title: "Gone",
      archived_at: ~U[2026-01-01 00:00:00Z]
    })

    custom_field_fixture(team, %{target: "incident", title: "Agency"})
    custom_field_fixture(team_fixture(), %{target: "member", title: "Theirs"})

    titles = fn viewer ->
      team.id |> CustomField.member_fields(viewer) |> Enum.map(& &1.title) |> Enum.sort()
    end

    assert titles.(:team_admin) ==
             ["Areas", "Call sign", "Heritage", "Hidden and restricted", "Notes", "Year of birth"]

    assert titles.(:self) == ["Areas", "Call sign", "Heritage", "Year of birth"]
  end
end
