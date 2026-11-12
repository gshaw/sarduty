defmodule App.OpsTest do
  use App.DataCase

  import App.AccountsFixtures
  import ExUnit.CaptureIO

  alias App.Model.Event
  alias App.Ops
  alias App.Ops.Query

  setup do
    %{admin: user_fixture(is_admin: true)}
  end

  defp request(admin, task, args, extra \\ %{}) do
    Map.merge(
      %{
        "task" => task,
        "args" => args,
        "email" => admin.email,
        "via" => "Claude Code",
        "why" => "#517"
      },
      extra
    )
  end

  defp events, do: Event |> where([e], e.kind == :prod_task) |> Repo.all()

  test "lists the tasks without recording anything" do
    assert {:ok, lines} = Ops.run(%{"task" => "list"})
    assert Enum.any?(lines, &String.starts_with?(&1, "query SQL"))
    assert Enum.any?(lines, &String.starts_with?(&1, "fix restore-team"))
    assert events() == []
  end

  test "runs a query and records who, why, and what", %{admin: admin} do
    sql = "select 1 + 1 as two, null as missing, 'a  b' as text"

    assert {:ok, ["two  missing  text", "2    NULL     a b", summary]} =
             admin |> request("query", [sql]) |> Ops.run()

    assert summary =~ ~r/\A1 row in \d+ ms, recorded\z/

    assert [%Event{user_id: user_id, data: data}] = events()
    assert user_id == admin.id

    assert data == %{
             "task" => "query",
             "args" => [sql],
             "why" => "#517",
             "via" => "Claude Code",
             "outcome" => "ok",
             "rows" => 1
           }
  end

  test "a query can't write, and the attempt is recorded", %{admin: admin} do
    assert {:error, [error, summary]} =
             admin |> request("query", ["delete from teams"]) |> Ops.run()

    assert error =~ "readonly"
    assert summary =~ "Failed after"

    assert [%Event{data: %{"outcome" => "failed", "error" => ^error}}] = events()
  end

  test "a query prints 50 rows and says there were more" do
    sql =
      "with recursive n(i) as (select 1 union all select i + 1 from n where i < 60) select i from n"

    assert {:ok, %{rows: rows, note: note}} = Query.run([sql])
    assert length(rows) == 50
    assert note =~ "Stopped at 50 rows"
  end

  test "a query stops at its time limit" do
    endless =
      "with recursive n(i) as (select 1 union all select i + 1 from n) select count(*) from n"

    assert {:error, "Stopped at the 200 ms limit. Aggregate in SQL, or narrow it."} =
             Query.query(endless, 200)
  end

  test "refuses a run with no why, an unknown admin, or the wrong verb", %{admin: admin} do
    assert {:error, [why]} = admin |> request("query", ["select 1"], %{"why" => " "}) |> Ops.run()
    assert why =~ "--why"

    member = user_fixture()
    assert {:error, [who]} = member |> request("query", ["select 1"]) |> Ops.run()
    assert who =~ "isn't a SAR Duty admin"

    assert {:error, ["restore-team changes data: bin/prod fix restore-team"]} =
             admin |> request("restore-team", ["x.db", "1"]) |> Ops.run()

    assert {:error, ["query only reads: bin/prod query"]} =
             admin |> request("query", ["select 1"], %{"fix" => true}) |> Ops.run()

    assert {:error, ["No task called nope. bin/prod list shows them."]} =
             admin |> request("nope", []) |> Ops.run()

    assert events() == []
  end

  test "a write task runs through fix", %{admin: admin} do
    assert {:error, ["no copy at /nowhere.db", _summary]} =
             admin
             |> request("restore-team", ["/nowhere.db", "15"], %{"fix" => true})
             |> Ops.run()

    assert [%Event{data: %{"task" => "restore-team", "args" => ["/nowhere.db", "15"]}}] = events()
  end

  test "makes a login an admin", %{admin: admin} do
    other = user_fixture()
    fix = %{"fix" => true}

    assert {:ok, [line, _summary]} =
             admin |> request("make-admin", [other.email], fix) |> Ops.run()

    assert line == "#{other.email} is an admin now."
    assert Repo.reload!(other).is_admin

    assert {:error, ["No login for new@example.org. They log in once first.", _summary]} =
             admin |> request("make-admin", ["new@example.org"], fix) |> Ops.run()
  end

  test "main prints the answer between the markers bin/prod reads", %{admin: admin} do
    encoded = admin |> request("query", ["select 7 as n"]) |> Jason.encode!() |> Base.encode64()
    output = capture_io(fn -> Ops.main(encoded) end)

    assert ["--- bin/prod ---", "n", "7", _summary, "--- ok ---"] =
             String.split(output, "\n", trim: true)

    assert capture_io(fn -> Ops.main("not base64!") end) =~ "--- failed ---"
  end
end
