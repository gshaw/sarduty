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

  test "anyone else is refused, another organization's admin too", %{form: form} do
    other = user_fixture()
    organization_admin_fixture(organization_fixture(), other.email)

    for user <- [user_fixture(), other] do
      assert SetFormState.call(form, :on, user) == {:error, :forbidden}
    end

    assert Repo.reload!(form).state == :off
  end
end
