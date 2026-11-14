defmodule App.Operation.SetTeamFormsTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.Model.Event
  alias App.Operation.SetTeamForms

  test "a SAR Duty admin turns team forms on and off; a team admin cannot" do
    %{user: team_admin, team: team} = user_with_team_fixture()
    admin = make_admin(AccountsFixtures.user_fixture())

    assert SetTeamForms.call(team, true, team_admin) == {:error, :not_allowed}
    assert {:ok, %{forms_enabled: true}} = SetTeamForms.call(team, true, admin)
    assert SetTeamForms.call(team, false, team_admin) == {:error, :not_allowed}
    assert {:ok, %{forms_enabled: false}} = SetTeamForms.call(team, false, admin)

    assert [:team_forms_turned_off, :team_forms_turned_on] =
             Event
             |> where(team_id: ^team.id)
             |> order_by(desc: :id)
             |> select([e], e.kind)
             |> Repo.all()
  end
end
