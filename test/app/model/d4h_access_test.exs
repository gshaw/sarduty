defmodule App.Model.D4HAccessTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.WhoAmI
  alias App.Model.D4HAccess
  alias App.Model.Team

  defp all_rights do
    for feature <- D4HAccess.features(), {resource, action} <- feature.needs, reduce: %{} do
      acc -> put_in(acc, [Access.key(resource, %{}), action], true)
    end
  end

  defp ids(features), do: Enum.map(features, & &1.id)

  test "a nil map, a Records team's or one never checked, refuses nothing" do
    assert D4HAccess.refused(nil) == []
    assert Team.d4h_can?(%Team{d4h_permissions: nil}, :groups)
  end

  test "a key with every right refuses nothing" do
    assert D4HAccess.refused(all_rights()) == []
  end

  test "one false right refuses each feature that needs it" do
    rights = put_in(all_rights(), ["Equipment", "UPDATE"], false)

    assert ids(D4HAccess.refused(rights)) == [:equipment, :field_values]
    refute Team.d4h_can?(%Team{d4h_permissions: rights}, :equipment)
    assert Team.d4h_can?(%Team{d4h_permissions: rights}, :equipment_usage)
  end

  test "a right D4H leaves out counts as refused" do
    rights = Map.delete(all_rights(), "Whiteboard")
    assert ids(D4HAccess.refused(rights)) == [:whiteboard]
  end

  # #727 decision 3: adding someone to a group is MemberGroup.UPDATE.
  test "changing groups needs MemberGroup.UPDATE" do
    rights = put_in(all_rights(), ["MemberGroup", "UPDATE"], false)
    assert ids(D4HAccess.refused(rights)) == [:groups]
  end

  # South Fraser's Editor key on 2026-10-29: no custom field definitions, no saved
  # places, no settings. SAR Duty uses none of those, so it refuses nothing.
  test "an Editor's key as D4H sends it today refuses nothing SAR Duty does" do
    rights =
      all_rights()
      |> put_in(["Incident", "CREATE_CUSTOM_FIELDS"], false)
      |> put_in(["Equipment", "UPDATE_CUSTOM_FIELDS"], false)
      |> Map.put("LocationBookmark", %{"CREATE" => false})
      |> Map.put("Setting", %{"UPDATE" => false})

    assert D4HAccess.refused(rights) == []
  end

  test "whoami's rights come from its context, and Records sends none" do
    team = %{"resourceType" => "Team", "id" => 7, "title" => "Coast Range SAR"}
    member = %{"id" => 70, "name" => "SAR Duty", "owner" => team}
    rights = %{"Team" => %{"READ" => true}}

    d4h = WhoAmI.build(%{"members" => [member], "context" => %{"permissions" => rights}})
    records = WhoAmI.build(%{"members" => [member]})

    assert d4h.permissions == rights
    assert records.permissions == nil
  end
end
