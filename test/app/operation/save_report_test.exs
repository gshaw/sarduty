defmodule App.Operation.SaveReportTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.Model.SavedReport
  alias App.Operation.SaveReport

  describe "call/5" do
    setup do
      %{team: team_fixture(), user: AccountsFixtures.user_fixture()}
    end

    test "saves a report whose query runs, with who made it", %{team: team, user: user} do
      params = %{
        "name" => "Hours by member",
        "about" => "Mine",
        "query" => "select name from members"
      }

      assert {:ok, report} = SaveReport.call(team, user, nil, params)
      assert report.created_by_user_id == user.id
      assert SavedReport.get(team, report.id).query == "select name from members"
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
  end
end
