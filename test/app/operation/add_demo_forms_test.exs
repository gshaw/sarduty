defmodule App.Operation.AddDemoFormsTest do
  # WESARA's made-up forms (#963), on for a demo's organization and the dev WESARA.
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.Form
  alias App.Operation.AddDemoForms
  alias App.Operation.SaveForm
  alias App.Operation.SeedCoastRange
  alias App.SilverBasin

  defp silver_basin do
    rows = SeedCoastRange.insert(Repo, SilverBasin.build(DateTime.utc_now()))
    rows[{:team, :silverbasin}]
  end

  test "adds the Task report with its page, on, for every team in the organization" do
    team = silver_basin()
    organization = organization_fixture([team])

    assert [%Form{name: "Task report", state: :on} = form] = AddDemoForms.call(organization)
    assert Form.page_bytes(form) == File.read!("priv/forms/wesara/task_report.pdf")
    assert [%Form{id: id}] = team |> Repo.reload!() |> Form.shown_for()
    assert id == form.id
  end

  # Saving a form runs it on every team in the organization, so it passes there.
  test "saves on Silver Basin SAR, WESARA's second team" do
    organization = organization_fixture([silver_basin()])

    for path <- AddDemoForms.paths() do
      text = File.read!(path <> ".txt")
      page = File.read!(path <> ".pdf")

      assert {:ok, _form} =
               SaveForm.call(organization, nil, text, page, user_fixture(%{is_admin: true}))
    end
  end
end
