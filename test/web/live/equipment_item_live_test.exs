defmodule Web.EquipmentItemLiveTest do
  use Web.ConnCase, async: true

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.D4HChange

  test "shows the item's custom fields (#681)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    custom_field_fixture(team, %{
      d4h_custom_field_id: 603,
      target: "equipment",
      title: "Equipment Description"
    })

    item = equipment_item_fixture(team, %{custom_values: %{"603" => "Orange dry bag"}})

    conn = log_in_user(conn, user)

    # Not in the sidebar (#705): Activities and Fields tabs.
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/equipment/#{item.id}")
    refute has_element?(lv, "#item-fields")
    assert has_element?(lv, "#item-activities")
    assert has_element?(lv, "nav.tabs a[href$='/fields']", "Fields")
    assert has_element?(lv, "#item-actions-change-fields[href$='/fields/edit']")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/equipment/#{item.id}/fields")
    assert has_element?(lv, "#item-fields-603", "Orange dry bag")
    refute has_element?(lv, "#item-activities")
    assert has_element?(lv, "#item-fields-change[href$='/equipment/#{item.id}/fields/edit']")
  end

  test "an item with no fields has Activities and History, no Fields", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    item = equipment_item_fixture(team)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/equipment/#{item.id}")

    assert has_element?(lv, "#item-activities")
    assert has_element?(lv, "#item-details dd", "In service")
    assert has_element?(lv, "nav.tabs a[href$='/history']", "History")
    refute has_element?(lv, "nav.tabs a[href$='/fields']")
    refute has_element?(lv, "#item-actions-change-fields")
  end

  test "History shows Change item and what the refresh saw (#1014)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    custom_field_fixture(team, %{d4h_custom_field_id: 604, target: "equipment", title: "Notes"})
    item = equipment_item_fixture(team, %{title: "AED 2"})

    change_set =
      ChangeSet.propose!(
        %ChangeSet{team_id: team.id, source: :edit, proposed_by_user_id: user.id},
        [
          %ChangeSetRow{
            action: :update_equipment_item,
            d4h_record_id: item.d4h_equipment_id,
            old_value: %{"custom_values" => %{"604" => nil}},
            new_value: %{"custom_values" => %{"604" => "Pads replaced"}}
          }
        ]
      )

    [row] = change_set.rows
    ChangeSetRow.record!(row, {:applied, item.d4h_equipment_id}, ~U[2026-11-10 18:00:00.000000Z])

    D4HChange.insert!(%D4HChange{
      team_id: team.id,
      equipment_item_id: item.id,
      record_kind: :equipment_item,
      action: :changed,
      fields: ["status"],
      old_value: %{"status" => "operational"},
      new_value: %{"status" => "unserviceable"},
      seen_after: ~U[2026-11-11 17:00:00.000000Z],
      seen_at: ~U[2026-11-11 17:10:00.000000Z]
    })

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/equipment/#{item.id}/history")

    assert page_title(lv) =~ "AED 2 · History"
    assert has_element?(lv, "#item-history", "Notes changed to Pads replaced")
    assert has_element?(lv, "#item-history", "Status changed from in service to unserviceable")
    assert has_element?(lv, "#item-history", "Someone outside SAR Duty")
    refute has_element?(lv, "#item-activities")
  end

  test "History on an item with none says so", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    item = equipment_item_fixture(team)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/equipment/#{item.id}/history")

    assert has_element?(lv, "#item-history-empty", "November 2026")
  end
end
