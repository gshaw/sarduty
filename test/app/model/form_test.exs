defmodule App.Model.FormTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Form

  # A team in an organization with one form on, and its own form testing (#1083).
  setup do
    organization = organization_fixture()

    team =
      team_fixture()
      |> Ecto.Changeset.change(organization_id: organization.id)
      |> Repo.update!()

    %{
      team: team,
      task_report: form_fixture(organization, %{state: :on}),
      debrief: form_fixture(team, %{name: "Debrief", state: :testing})
    }
  end

  defp forms_on(team),
    do: team |> Ecto.Changeset.change(forms_enabled: true) |> Repo.update!()

  test "a team's own forms show only while team forms are on",
       %{team: team, task_report: task_report, debrief: debrief} do
    assert ids(Form.shown_for(team)) == [task_report.id]
    assert Form.get_shown(team, debrief.id) == nil
    refute Form.shown?(debrief, team)

    team = forms_on(team)

    assert ids(Form.shown_for(team)) == [debrief.id, task_report.id]
    assert Form.get_shown(team, "#{debrief.id}").id == debrief.id
    assert Form.shown?(debrief, team)
  end

  test "a team's form that's off isn't shown", %{team: team, debrief: debrief} do
    debrief |> Ecto.Changeset.change(state: :off) |> Repo.update!()
    refute team |> forms_on() |> Form.shown_for() |> ids() |> Enum.member?(debrief.id)
  end

  test "another team never sees a team's form", %{debrief: debrief} do
    other = forms_on(team_fixture())
    assert Form.shown_for(other) == []
    assert Form.get_shown(other, debrief.id) == nil
  end

  test "an organization's form replaces the team's of the same name",
       %{team: team, task_report: task_report} do
    own = form_fixture(team, %{state: :on})
    team = forms_on(team)

    assert own.name == task_report.name
    refute own.id in ids(Form.shown_for(team))
    assert Form.get_shown(team, own.id) == nil
  end

  test "get/2 and get_all/1 find an owner's own forms only",
       %{team: team, task_report: task_report, debrief: debrief} do
    assert ids(Form.get_all(team)) == [debrief.id]
    assert Form.get(team, debrief.id).id == debrief.id
    assert Form.get(team, task_report.id) == nil
    assert Form.get(team_fixture(), debrief.id) == nil
  end

  test "off_text/1 sends an organization's form to its organization, and a team's to no one",
       %{task_report: task_report, debrief: debrief} do
    assert Form.off_text(task_report) ==
             "This form is turned off. Ask your organization to turn it on."

    assert Form.off_text(debrief) == "This form is turned off."
  end

  defp ids(forms), do: Enum.map(forms, & &1.id)
end
