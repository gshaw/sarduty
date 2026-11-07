defmodule App.Model.SavedPDFTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.SavedPDF
  alias App.Model.SavedPDFFile

  setup do
    team = team_fixture(%{name: "Coast Range SAR"})
    %{team: team, activity: activity_fixture(team, %{activity_kind: "incident"})}
  end

  defp pdf(content), do: %{content: content, title: "Task report", filename: "task-report.pdf"}

  describe "a form's PDF for an activity" do
    test "keeps who made it, when, and the values it printed",
         %{activity: activity, team: team} do
      user = user_fixture()
      keep = %{"people_helped" => 3}

      saved = SavedPDF.add_for_activity!(activity, user, pdf("%PDF-1"), keep)

      assert %SavedPDF{team_id: team_id, user_id: user_id, byte_size: 6, inserted_at: %DateTime{}} =
               saved

      assert team_id == team.id
      assert user_id == user.id
      assert Repo.get!(SavedPDF, saved.id).keep == keep
      assert %{content: "%PDF-1", filename: "task-report.pdf"} = SavedPDF.attachment(saved)
    end

    test "saves each one, replacing none", %{activity: activity} do
      user = user_fixture()
      first = SavedPDF.add_for_activity!(activity, user, pdf("%PDF-1"))
      SavedPDF.add_for_activity!(activity, user, pdf("%PDF-2"))

      assert SavedPDF.attachment(first).content == "%PDF-1"
      assert Repo.aggregate(SavedPDF, :count) == 2
      assert Repo.aggregate(SavedPDFFile, :count) == 2
    end

    test "keeps it when its maker's login goes", %{activity: activity} do
      user = user_fixture()
      saved = SavedPDF.add_for_activity!(activity, user, pdf("%PDF-1"))

      Repo.delete!(user)

      assert %SavedPDF{user_id: nil} = Repo.get!(SavedPDF, saved.id)
    end
  end
end
