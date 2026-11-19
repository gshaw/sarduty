defmodule App.Operation.SetFormStateTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.Event
  alias App.Operation.SetFormState

  setup do
    organization = organization_fixture()
    %{organization: organization, form: form_fixture(organization)}
  end

  test "its organization admin sets it testing, on, and off (#970)",
       %{organization: organization, form: form} do
    user = user_fixture()
    organization_admin_fixture(organization, user.email)

    assert {:ok, %{state: :testing} = testing} = SetFormState.call(form, :testing, user)
    assert testing.user_id == user.id
    assert {:ok, %{state: :on} = on} = SetFormState.call(testing, :on, user)
    assert {:ok, %{state: :off}} = SetFormState.call(on, :off, user)

    assert [:form_turned_off, :form_turned_on, :form_set_testing] =
             Event |> order_by(desc: :id) |> select([e], e.kind) |> Repo.all()
  end

  test "a SAR Duty admin does too", %{form: form} do
    assert {:ok, %{state: :on}} = SetFormState.call(form, :on, user_fixture(%{is_admin: true}))
  end

  test "a team's form with no text yet stays off (#1083)" do
    form = form_fixture(team_fixture(), %{text: ""})
    admin = user_fixture(%{is_admin: true})

    assert SetFormState.call(form, :testing, admin) == {:error, :not_written}
    assert SetFormState.call(form, :on, admin) == {:error, :not_written}
    assert {:ok, %{state: :off}} = SetFormState.call(form, :off, admin)
  end

  test "anyone else is refused, another organization's admin too", %{form: form} do
    other = user_fixture()
    organization_admin_fixture(organization_fixture(), other.email)

    for user <- [user_fixture(), other] do
      assert SetFormState.call(form, :on, user) == {:error, :forbidden}
    end

    assert Repo.reload!(form).state == :off
  end

  describe "a team's own form (#1083)" do
    setup %{organization: organization} do
      team =
        team_fixture()
        |> Ecto.Changeset.change(forms_enabled: true, organization_id: organization.id)
        |> Repo.update!()

      %{team: team, own: form_fixture(team, %{name: "Debrief"})}
    end

    test "the team's admins set it, and the event names the team", %{team: team, own: own} do
      manager = manager_fixture(team)
      user = user_fixture(%{email: manager.email})

      assert {:ok, %{state: :testing}} = SetFormState.call(own, :testing, user)
      assert %Event{team_id: team_id} = Repo.get_by!(Event, kind: :form_set_testing)
      assert team_id == team.id
    end

    test "its organization's admins and another team's admins can't",
         %{organization: organization, own: own} do
      org_admin = user_fixture()
      organization_admin_fixture(organization, org_admin.email)
      other = manager_fixture(team_fixture())

      for user <- [org_admin, user_fixture(%{email: other.email})] do
        assert SetFormState.call(own, :on, user) == {:error, :forbidden}
      end
    end
  end
end
