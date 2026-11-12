defmodule App.Operation.DeleteTeamTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures
  import Swoosh.TestAssertions

  alias App.Adapter.D4H
  alias App.Adapter.FileStore
  alias App.Model.Event
  alias App.Model.PublishedPDF
  alias App.Model.Team
  alias App.Operation.DeleteTeam
  alias App.RecordsStub
  alias App.Repo
  alias App.Worker.SyncTeamChangesWorker

  # A team with a row in most kinds of table, reached through team_id and through
  # parents that have none (attendances, group members, awards, letters, certificates,
  # saved PDFs).
  defp full_team(name) do
    team = team_fixture(%{name: name})
    member = member_fixture(team)
    activity = activity_fixture(team)
    attendance_fixture(activity, member)
    qualification = qualification_fixture(team)
    qualification_award_fixture(qualification, member)
    certificate_fixture(member, qualification)
    group = group_fixture(team)
    group_member_fixture(group, member)
    endorsement = endorsement_fixture(team)
    endorsement_qualification_fixture(endorsement, qualification)
    group_rule_fixture(group, endorsement)
    member_card_fixture(member)
    # A letter, and the one it replaced (#970).
    old = tax_credit_letter_fixture(member)
    pdf = %{content: "%PDF-1.7", title: "A PDF", filename: "a.pdf"}
    attrs = %{team_id: team.id, name: old.name, subject: old.subject, member_id: member.id}

    {:ok, _pdf} =
      attrs
      |> Map.put(:code, PublishedPDF.generate_code())
      |> PublishedPDF.publish(%{attachment: pdf}, old.id)

    item = equipment_item_fixture(team)
    equipment_usage_fixture(activity, item)
    template_fixture(team, "Truck 1", [item])
    chore_fixture(member, chore_category_fixture(team))
    away_period_fixture(member, ~D[2026-01-01], ~D[2026-01-31])
    activity_photo_fixture(activity, %{member_id: member.id})
    team
  end

  setup do
    %{admin: make_admin(user_fixture()), team: full_team("Coast Range SAR")}
  end

  test "deletes every row the team has, and leaves other teams alone", %{
    admin: admin,
    team: team
  } do
    other = full_team("Valley SAR")
    other_counts = DeleteTeam.row_counts(other)
    assert map_size(DeleteTeam.row_counts(team)) > 15

    assert {:ok, %{rows: rows, snapshot: nil}} = DeleteTeam.call(team, "coast range sar ", admin)
    assert rows > 15

    refute Repo.get(Team, team.id)
    assert DeleteTeam.row_counts(team) == %{}
    assert DeleteTeam.row_counts(other) == other_counts
    # The sandbox never commits, so check the keys the commit would.
    assert %{rows: []} = Repo.query!("PRAGMA foreign_key_check")
  end

  # A team's files go with its rows (#1032): its activities' photos, and anything else
  # under its prefix in the file store, such as a file whose row never saved.
  test "deletes the team's files, and leaves another team's", %{admin: admin, team: team} do
    other = full_team("Valley SAR")
    photo = activity_photo_fixture(activity_fixture(team))
    accepted = activity_photo_fixture(activity_fixture(team), %{status: :accepted})
    theirs = activity_photo_fixture(activity_fixture(other))
    stray = "#{Team.file_prefix(team.id)}/activity-photos/no-row/tile.jpg"
    :ok = FileStore.put(stray, "bytes")

    assert {:ok, _result} = DeleteTeam.call(team, team.name, admin)

    for gone <- [photo, accepted] do
      refute Repo.reload(gone)
      assert gone |> activity_photo_files() |> Enum.all?(&(&1 == {:error, :not_found}))
    end

    assert FileStore.get(stray) == {:error, :not_found}
    assert Repo.reload(theirs)
    assert theirs |> activity_photo_files() |> Enum.all?(&match?({:ok, _bytes}, &1))
  end

  test "refuses a name that doesn't match", %{admin: admin, team: team} do
    assert {:error, :name_mismatch} = DeleteTeam.call(team, "Coast Range", admin)
    assert Repo.get(Team, team.id)
  end

  test "records the delete and emails the admins", %{admin: admin, team: team} do
    {:ok, _deleted} = DeleteTeam.call(team, team.name, admin)

    assert %Event{user_id: user_id, data: %{"subdomain" => subdomain, "reason" => "admin"}} =
             Repo.get_by!(Event, kind: :team_deleted)

    assert user_id == admin.id
    assert subdomain == team.subdomain
    assert_email_sent(subject: "Team deleted from SAR Duty: Coast Range SAR")
  end

  test "purge/2 with no user records the reason and emails nobody", %{team: team} do
    assert {:ok, %{snapshot: nil}} = DeleteTeam.purge(team, reason: :admin)

    assert %Event{user_id: nil, data: %{"reason" => "admin"}} =
             Repo.get_by!(Event, kind: :team_deleted)

    assert_no_email_sent()
  end

  test "a demo's delete records demo_deleted, not team_deleted (#857)", %{
    team: team
  } do
    assert {:ok, _result} = DeleteTeam.purge(team, reason: :demo)

    assert %Event{data: %{"reason" => "demo"}} = Repo.get_by!(Event, kind: :demo_deleted)
    refute Repo.get_by(Event, kind: :team_deleted)
  end

  test "deletes the team's waiting jobs and leaves another team's", %{team: team} do
    other = team_fixture()

    # Inserted as they wait, since tests run jobs inline.
    %{"team_id" => team.id} |> SyncTeamChangesWorker.new() |> Repo.insert!()
    %{"team_id" => other.id} |> SyncTeamChangesWorker.new() |> Repo.insert!()

    {:ok, _deleted} = DeleteTeam.purge(team, reason: :admin)

    assert [%{args: %{"team_id" => other_id}}] = Repo.all(Oban.Job)
    assert other_id == other.id
  end

  describe "a team on SAR Duty Records" do
    setup do
      %{records_team: team_fixture(%{name: "Fjord SAR", d4h_api_host: D4H.records_host()})}
    end

    test "goes from Records first, held there 7 days", %{admin: admin, records_team: team} do
      RecordsStub.stub(fn "DELETE", _path, _body -> {200, %{"deletesOn" => "2026-11-12"}} end)

      assert {:ok, _deleted} = DeleteTeam.call(team, "Fjord SAR", admin)

      path = "/v3/sarduty/teams/#{team.d4h_team_id}"
      assert_received {:records, "DELETE", ^path, nil}
      refute Repo.get(Team, team.id)
      assert %Event{data: %{"records" => true}} = Repo.get_by!(Event, kind: :team_deleted)

      assert_email_sent(fn email ->
        assert email.text_body =~ "Its SAR Duty Records team is switched off, and goes in 7 days."
      end)
    end

    test "a team Records doesn't have goes", %{records_team: team} do
      RecordsStub.stub(fn "DELETE", _path, _body -> {404, %{"title" => "Not Found"}} end)
      assert {:ok, _deleted} = DeleteTeam.purge(team, reason: :admin)
      refute Repo.get(Team, team.id)
    end

    test "a refusal deletes nothing", %{admin: admin, records_team: team} do
      RecordsStub.stub(fn "DELETE", _path, _body -> {500, %{"title" => "Down"}} end)

      assert {:error, %D4H.Error{}} = DeleteTeam.call(team, "Fjord SAR", admin)
      assert Repo.get(Team, team.id)
      refute Repo.get_by(Event, kind: :team_deleted)
      assert_no_email_sent()
    end
  end

  # The copy reads the database file on its own connection, which can't see this test's
  # sandbox rows, so this checks the schema and every table's WHERE, not the rows.
  @tag :tmp_dir
  test "write_copy/3 writes every table, with the team's rows only", %{tmp_dir: dir} do
    path = Path.join(dir, "copy.db")
    assert :ok = DeleteTeam.write_copy(path, Repo.config()[:database], 999_999)

    {:ok, copy} = Exqlite.Sqlite3.open(path)

    for {table, _where} <- DeleteTeam.scopes(999_999) do
      {:ok, statement} = Exqlite.Sqlite3.prepare(copy, ~s|SELECT count(*) FROM "#{table}"|)
      assert {:row, [0]} = Exqlite.Sqlite3.step(copy, statement)
    end

    Exqlite.Sqlite3.close(copy)
  end

  @tag :tmp_dir
  test "a copy that fails leaves no file", %{tmp_dir: dir} do
    path = Path.join(dir, "copy.db")

    assert_raise RuntimeError, fn ->
      DeleteTeam.write_copy(path, Path.join(dir, "none/x.db"), 1)
    end

    refute File.exists?(path)
  end

  defp tables do
    %{rows: rows} =
      Repo.query!(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT IN ('schema_migrations', 'teams')"
      )

    List.flatten(rows)
  end

  defp columns(table) do
    %{rows: rows} = Repo.query!(~s{SELECT name FROM pragma_table_info('#{table}')})
    List.flatten(rows)
  end

  defp keys(table) do
    %{rows: rows} =
      Repo.query!(~s{SELECT "from", "table" FROM pragma_foreign_key_list('#{table}')})

    Enum.map(rows, &List.to_tuple/1)
  end

  # A new table with a team_id belongs in @team_tables. Don't skip this: a team deleted
  # without it leaves rows behind, or fails the delete at commit.
  test "every table with a team_id is deleted" do
    with_team_id = tables() |> Enum.filter(&("team_id" in columns(&1))) |> Enum.sort()
    assert Enum.sort(DeleteTeam.team_tables()) == with_team_id
  end

  test "every row hanging off a team's rows without a team_id is deleted" do
    team_tables = DeleteTeam.team_tables()

    hanging =
      for table <- tables(),
          "team_id" not in columns(table),
          {key, parent} <- keys(table),
          parent in team_tables,
          do: {table, key, parent}

    assert Enum.sort(DeleteTeam.child_tables()) == Enum.sort(hanging)
  end
end
