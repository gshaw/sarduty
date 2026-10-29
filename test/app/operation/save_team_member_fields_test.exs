defmodule App.Operation.SaveTeamMemberFieldsTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Model.D4HChange
  alias App.Model.Event
  alias App.Model.Member
  alias App.Operation.RecordD4HChanges
  alias App.Operation.RefreshD4HData.UpsertCustomFields
  alias App.Operation.SaveTeamMemberFields

  @now ~U[2026-10-28 12:00:00.000000Z]

  defp field(id, title, restricted),
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

  test "copies only the picked, unrestricted fields, and reads the members at once" do
    %{user: user, team: team} = user_with_team_fixture()
    team = team |> Ecto.Changeset.change(d4h_access_key: "key") |> Repo.update!()
    member = member_fixture(team, %{custom_values: %{"9" => "stale"}})

    UpsertCustomFields.save(
      team.id,
      [field(630, "Radio Call Sign", false), field(855, "Date of Birth", true)],
      @now
    )

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      row = d4h_member(member, %{630 => "SF 12", 855 => "1970-01-01"})
      Req.Test.json(conn, %{"results" => [row], "totalSize" => 1})
    end)

    assert :ok = SaveTeamMemberFields.call(team, ["630", "855", "nonsense"], user)

    assert [%{d4h_custom_field_id: 630, copy_values: true}] =
             team.id |> CustomField.get_all("member") |> Enum.filter(& &1.copy_values)

    assert Repo.get!(Member, member.id).custom_values == %{"630" => "SF 12"}
    assert %{data: %{"d4h_custom_field_ids" => [630]}} = Event.get_last(:member_fields_changed)
  end

  test "picking none clears every copied value" do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{custom_values: %{"630" => "SF 12"}})
    UpsertCustomFields.save(team.id, [field(630, "Radio Call Sign", false)], @now)

    assert :ok = SaveTeamMemberFields.call(team, [], user)

    assert Repo.get!(Member, member.id).custom_values == nil
    refute team.id |> CustomField.get_all("member") |> Enum.any?(& &1.copy_values)
  end

  test "a member's field changes are named in history, never their values" do
    team = team_fixture(%{d4h_refreshed_at: @now, d4h_synced_at: @now})
    member = member_fixture(team, %{custom_values: %{"630" => "SF 12"}})
    UpsertCustomFields.save(team.id, [field(630, "Radio Call Sign", false)], @now)
    changed = %{member | custom_values: %{"630" => "SF 13"}}

    RecordD4HChanges.recording(team, @now, fn ->
      RecordD4HChanges.record(:member, member, changed)
    end)

    assert [change] = Repo.all(D4HChange)
    assert change.new_value == %{"custom_values" => ["Radio Call Sign"]}
    assert change.old_value == %{}
  end
end
