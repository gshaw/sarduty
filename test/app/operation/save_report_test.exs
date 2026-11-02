defmodule App.Operation.SaveReportTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.Model.ReportVersion
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

  describe "versions (#834)" do
    setup do
      %{team: team_fixture(), user: AccountsFixtures.user_fixture()}
    end

    test "every save appends a version, with What changed only on a change",
         %{team: team, user: user} do
      params = %{"name" => "Groups", "query" => "select title from groups", "change" => "x"}
      {:ok, report} = SaveReport.call(team, user, nil, params, DateTime.utc_now(), "Claude")

      {:ok, report} =
        SaveReport.call(team, user, report, %{
          "query" => "select title from groups order by title",
          "change" => "Sorted by title"
        })

      {:ok, report} = SaveReport.call(team, user, report, %{"name" => "All groups"})

      assert [third, second, first] = ReportVersion.get_all(report)

      assert {first.query, first.change, first.agent} ==
               {"select title from groups", nil, "Claude"}

      assert {second.change, second.agent} == {"Sorted by title", nil}
      assert {third.name, third.change, third.user_id} == {"All groups", nil, user.id}
      refute Map.has_key?(third, :values)
    end

    test "What changed is 100 characters at most", %{team: team, user: user} do
      {:ok, report} =
        SaveReport.call(team, user, nil, %{"name" => "G", "query" => "select title from groups"})

      assert {:error, changeset} =
               SaveReport.call(team, user, report, %{"change" => String.duplicate("x", 101)})

      assert {"What changed must be 100 characters or fewer", _} = changeset.errors[:change]
      assert length(ReportVersion.get_all(report)) == 1
    end

    test "a deleted report waits 30 days with its versions, and Restore brings it back",
         %{team: team, user: user} do
      {:ok, report} =
        SaveReport.call(team, user, nil, %{"name" => "G", "query" => "select title from groups"})

      now = ~U[2026-11-02 12:00:00Z]
      SaveReport.delete(report, now)
      assert SavedReport.get(team, report.id) == nil
      assert [%{id: id}] = SavedReport.get_deleted(team)
      assert id == report.id

      assert {:ok, _restored} = SaveReport.restore(team, report.id)
      assert SavedReport.get(team, report.id)
      assert SaveReport.restore(team, report.id) == :error

      SaveReport.delete(report, now)
      assert now |> DateTime.add(29, :day) |> SavedReport.prune_deleted() == 0
      assert now |> DateTime.add(31, :day) |> SavedReport.prune_deleted() == 1
      assert SavedReport.get_deleted(team) == []
      assert App.Repo.all(ReportVersion) == []
    end

    test "another team's deleted report can't be restored", %{team: team, user: user} do
      {:ok, report} =
        SaveReport.call(team, user, nil, %{"name" => "G", "query" => "select title from groups"})

      SaveReport.delete(report)
      assert SaveReport.restore(team_fixture(), report.id) == :error
    end
  end
end
