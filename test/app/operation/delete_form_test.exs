defmodule App.Operation.DeleteFormTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.Event
  alias App.Model.Form
  alias App.Model.FormPage
  alias App.Operation.DeleteForm

  setup do
    team = team_fixture()
    manager = manager_fixture(team)

    %{
      team: team,
      form: form_fixture(team, %{name: "Debrief"}),
      alex: user_fixture(%{email: manager.email})
    }
  end

  test "a team admin deletes a form no PDF was published from, with its page",
       %{team: team, form: form, alex: alex} do
    assert DeleteForm.allowed?(form, alex)
    assert DeleteForm.call(form, alex) == :ok

    refute Repo.get(Form, form.id)
    refute Repo.get_by(FormPage, form_id: form.id)

    assert %Event{team_id: team_id, data: %{"name" => "Debrief"}} =
             Repo.get_by!(Event, kind: :form_deleted)

    assert team_id == team.id
  end

  test "once a PDF was published from it, it's turned off instead",
       %{team: team, form: form, alex: alex} do
    team
    |> member_fixture()
    |> tax_credit_letter_fixture()
    |> Ecto.Changeset.change(form_id: form.id)
    |> Repo.update!()

    refute DeleteForm.allowed?(form, alex)
    assert DeleteForm.call(form, alex) == {:error, :published}
    assert Repo.get(Form, form.id)
  end

  test "anyone who can't turn it on or off can't delete it", %{form: form} do
    other = manager_fixture(team_fixture())

    for user <- [user_fixture(), user_fixture(%{email: other.email})] do
      refute DeleteForm.allowed?(form, user)
      assert DeleteForm.call(form, user) == {:error, :forbidden}
    end

    assert Repo.get(Form, form.id)
  end
end
