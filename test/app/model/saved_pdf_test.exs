defmodule App.Model.SavedPDFTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.SavedPDF
  alias App.Model.SavedPDFFile

  setup do
    team = team_fixture(%{name: "Coast Range SAR"})
    form = [team] |> organization_fixture() |> form_fixture(%{version: 2})
    %{team: team, form: form, activity: activity_fixture(team, %{activity_kind: "incident"})}
  end

  defp pdf(content), do: %{content: content, title: "Task report", filename: "task-report.pdf"}

  describe "a form's PDF for an activity" do
    test "keeps its form and version, who made it, when, and the values it printed",
         %{activity: activity, team: team, form: form} do
      user = user_fixture()
      keep = %{"people_helped" => 3}

      saved = SavedPDF.add_for_form!(form, activity, user, pdf("%PDF-1"), keep)

      assert %SavedPDF{team_id: team_id, user_id: user_id, byte_size: 6, inserted_at: %DateTime{}} =
               saved

      assert %SavedPDF{form_id: form_id, form_version: 2} = saved
      assert form_id == form.id
      assert team_id == team.id
      assert user_id == user.id
      assert Repo.get!(SavedPDF, saved.id).keep == keep
      assert %{content: "%PDF-1", filename: "task-report.pdf"} = SavedPDF.attachment(saved)
    end

    test "saves each one, replacing none", %{activity: activity, form: form} do
      user = user_fixture()
      first = SavedPDF.add_for_form!(form, activity, user, pdf("%PDF-1"))
      SavedPDF.add_for_form!(form, activity, user, pdf("%PDF-2"))

      assert SavedPDF.attachment(first).content == "%PDF-1"
      assert Repo.aggregate(SavedPDF, :count) == 2
      assert Repo.aggregate(SavedPDFFile, :count) == 2
    end

    test "keeps it when its maker's login goes", %{activity: activity, form: form} do
      user = user_fixture()
      saved = SavedPDF.add_for_form!(form, activity, user, pdf("%PDF-1"))

      Repo.delete!(user)

      assert %SavedPDF{user_id: nil} = Repo.get!(SavedPDF, saved.id)
    end

    test "keeps it when its form goes", %{activity: activity, form: form} do
      saved = SavedPDF.add_for_form!(form, activity, user_fixture(), pdf("%PDF-1"))

      Repo.delete!(form)

      assert %SavedPDF{form_id: nil, form_version: 2} = Repo.get!(SavedPDF, saved.id)
      assert SavedPDF.attachment(saved).content == "%PDF-1"
    end

    test "counts each form's since a moment, every team's together", %{form: form} do
      other = team_fixture()
      user = user_fixture()

      for activity <- [activity_fixture(other), activity_fixture(other)],
          do: SavedPDF.add_for_form!(form, activity, user, pdf("%PDF-1"))

      past = DateTime.add(DateTime.utc_now(), -60)
      assert SavedPDF.form_counts([form.id], past) == %{form.id => 2}
      assert SavedPDF.form_counts([form.id], DateTime.add(past, 120)) == %{}
    end
  end
end
