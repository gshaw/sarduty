defmodule App.Operation.SetFormEnabledTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.Event
  alias App.Operation.SetFormEnabled

  setup do
    organization = organization_fixture()
    %{organization: organization, form: form_fixture(organization)}
  end

  test "its organization admin turns it on and off", %{organization: organization, form: form} do
    user = user_fixture()
    organization_admin_fixture(organization, user.email)

    assert {:ok, %{enabled: true} = on} = SetFormEnabled.call(form, true, user)
    assert on.user_id == user.id
    assert {:ok, %{enabled: false}} = SetFormEnabled.call(on, false, user)

    assert [:form_turned_off, :form_turned_on] =
             Event |> order_by(desc: :id) |> select([e], e.kind) |> Repo.all()
  end

  test "a SAR Duty admin does too", %{form: form} do
    assert {:ok, %{enabled: true}} =
             SetFormEnabled.call(form, true, user_fixture(%{is_admin: true}))
  end

  test "anyone else is refused, another organization's admin too", %{form: form} do
    other = user_fixture()
    organization_admin_fixture(organization_fixture(), other.email)

    for user <- [user_fixture(), other] do
      assert SetFormEnabled.call(form, true, user) == {:error, :forbidden}
    end

    refute Repo.reload!(form).enabled
  end
end
