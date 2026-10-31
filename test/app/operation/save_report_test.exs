defmodule App.Operation.SaveReportTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.Model.SavedReport
  alias App.Operation.SaveReport

  describe "slug/2" do
    test "a slug comes from the name, and steps around ones taken" do
      assert SaveReport.slug("Swiftwater hours, 2 years!", []) == "swiftwater-hours-2-years"
      assert SaveReport.slug("Hours by member", ["hours-by-member"]) == "hours-by-member-2"

      assert SaveReport.slug("Hours by member", ["hours-by-member", "hours-by-member-2"]) ==
               "hours-by-member-3"

      assert SaveReport.slug("!!!", []) == "report"
    end
  end

  describe "call/5" do
    setup do
      %{team: team_fixture(), user: AccountsFixtures.user_fixture()}
    end

    test "saves a report whose query runs, with a slug no built-in report has", %{
      team: team,
      user: user
    } do
      params = %{
        "name" => "Hours by member",
        "about" => "Mine",
        "query" => "select name from members"
      }

      assert {:ok, report} = SaveReport.call(team, user, nil, params)
      assert report.slug == "hours-by-member-2"
      assert report.created_by_user_id == user.id
      assert SavedReport.get_by_slug(team, report.slug).query == "select name from members"
    end

    test "a query that cannot run is refused, with its line", %{team: team, user: user} do
      params = %{"name" => "Broken", "query" => "select name\nfrom members\nwhere nme = 'x'"}

      assert {:error, changeset} = SaveReport.call(team, user, nil, params)

      assert {"Line 3: members has no field nme. Did you mean name?", []} =
               changeset.errors[:query]
    end

    test "a name is needed", %{team: team, user: user} do
      assert {:error, changeset} =
               SaveReport.call(team, user, nil, %{"query" => "select name from members"})

      assert {"Enter a name for the report", _} = changeset.errors[:name]
    end

    test "a renamed report keeps its slug, so links to it still work", %{team: team, user: user} do
      {:ok, report} =
        SaveReport.call(team, user, nil, %{
          "name" => "First",
          "query" => "select name from members"
        })

      {:ok, renamed} = SaveReport.call(team, user, report, %{"name" => "Second"})
      assert {renamed.name, renamed.slug} == {"Second", "first"}
    end
  end
end
