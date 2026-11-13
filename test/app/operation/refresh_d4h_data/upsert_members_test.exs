defmodule App.Operation.RefreshD4HData.UpsertMembersTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.D4HChange
  alias App.Model.Member
  alias App.Operation.RecordD4HChanges
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.UpsertCustomFields
  alias App.Operation.RefreshD4HData.UpsertMembers

  # 11 pm on Sep 30 in Vancouver.
  @now ~U[2026-10-01 06:00:00Z]
  @saved_at ~U[2026-10-01 06:00:00.000000Z]

  test "marks this team's members D4H no longer lists as retired, as of today" do
    team = team_fixture()
    listed = member_fixture(team)
    missing = member_fixture(team)
    retired = member_fixture(team, %{left_at: ~U[2025-01-01 08:00:00Z]})
    other = member_fixture(team_fixture())

    UpsertMembers.mark_retired(team, MapSet.new([listed.d4h_member_id]), @now)

    assert Repo.get(Member, listed.id).left_at == nil
    # The start of Sep 30 on the team's clock.
    assert Repo.get(Member, missing.id).left_at == ~U[2026-09-30 07:00:00Z]
    assert Repo.get(Member, retired.id).left_at == ~U[2025-01-01 08:00:00Z]
    assert Repo.get(Member, other.id).left_at == nil
  end

  # D4H keeps both as the day at 00:00 UTC, the evening before in Vancouver (#1058).
  test "a join and leave date are kept as the start of D4H's day on a Pacific team's clock" do
    team = team_fixture(%{d4h_access_key: "team-key"})

    Req.Test.stub(D4H, fn conn ->
      Req.Test.json(conn, %{
        "results" => [
          %{
            "id" => 4242,
            "name" => "Sam Rivera",
            "owner" => %{"resourceType" => "Team", "id" => team.d4h_team_id},
            "email" => %{"value" => "sam@example.com"},
            "mobile" => %{"phone" => nil},
            "startsAt" => "2018-01-01T00:00:00.000Z",
            "endsAt" => "2026-07-15T00:00:00.000Z",
            "status" => "RETIRED"
          }
        ],
        "page" => 0,
        "pageSize" => 1,
        "totalSize" => 1
      })
    end)

    team |> D4H.build_context_from_team() |> UpsertMembers.call(team, Progress.quiet(team.id))

    member = Repo.get_by!(Member, team_id: team.id, d4h_member_id: 4242)
    assert member.joined_at == ~U[2018-01-01 08:00:00Z]
    assert member.left_at == ~U[2026-07-15 07:00:00Z]
    assert Service.Format.date_short(member.joined_at, team.timezone) =~ "Jan 1, 2018"
    assert Service.YearRange.year_in(member.joined_at, team.timezone) == 2018
  end

  defp member_field(id, title, restricted),
    do: %D4H.CustomField{
      d4h_custom_field_id: id,
      title: title,
      target: "member",
      field_type: "text",
      restricted: restricted
    }

  defp d4h_member(member, values) do
    %{
      "id" => member.d4h_member_id,
      "name" => member.name,
      "owner" => %{"resourceType" => "Team", "id" => 1},
      "email" => %{"value" => member.email},
      "mobile" => %{"phone" => nil},
      "customFieldValues" =>
        Enum.map(values, fn {id, value} -> %{"customField" => %{"id" => id}, "value" => value} end)
    }
  end

  defp read_members(team, values_for) do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      rows = Enum.map(values_for, fn {member, values} -> d4h_member(member, values) end)
      Req.Test.json(conn, %{"results" => rows, "totalSize" => length(rows)})
    end)

    RecordD4HChanges.recording(team, @saved_at, fn ->
      team |> D4H.build_context_from_team() |> UpsertMembers.call(team, Progress.quiet(team.id))
    end)
  end

  # The migration that keeps every member field (#1056) clears each member's values, so
  # the next read is a baseline: every field it brings, restricted ones too, and no
  # history for any of them.
  test "keeps every member field's values, and a read after the clear records nothing" do
    team = team_fixture(%{d4h_access_key: "key", d4h_refreshed_at: @now, d4h_synced_at: @now})
    member = member_fixture(team, %{custom_values: nil})

    UpsertCustomFields.save(
      team.id,
      [],
      [member_field(630, "Radio Call Sign", false), member_field(855, "Year of birth", true)],
      @saved_at
    )

    read_members(team, [{member, %{630 => "SF 12", 855 => "1970"}}])

    assert Repo.get!(Member, member.id).custom_values == %{"630" => "SF 12", "855" => "1970"}
    # The fixture's other details differ from D4H's row; only the fields matter here.
    changes = Repo.all(D4HChange)
    refute Enum.any?(changes, &Map.has_key?(&1.new_value, "custom_values"))
  end

  test "a member's field changes are named in history, never their values" do
    team = team_fixture(%{d4h_access_key: "key", d4h_refreshed_at: @now, d4h_synced_at: @now})
    member = member_fixture(team, %{custom_values: %{"855" => "1970"}})
    UpsertCustomFields.save(team.id, [], [member_field(855, "Year of birth", true)], @saved_at)

    read_members(team, [{member, %{855 => "1971"}}])

    assert [change] = Repo.all(D4HChange)
    assert change.new_value["custom_values"] == ["Year of birth"]
    refute Map.has_key?(change.old_value, "custom_values")
    refute inspect({change.old_value, change.new_value}) =~ "197"
  end
end
