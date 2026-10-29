defmodule Web.EquipmentItemLiveTest do
  use Web.ConnCase, async: true

  import App.DataFixtures
  import Phoenix.LiveViewTest

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

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/equipment/#{item.id}/fields")
    assert has_element?(lv, "#item-fields-603", "Orange dry bag")
    refute has_element?(lv, "#item-activities")
    assert has_element?(lv, "#item-fields-change[href$='/equipment/#{item.id}/fields/edit']")
  end

  test "an item with no fields has no tabs", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    item = equipment_item_fixture(team)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/equipment/#{item.id}")

    assert has_element?(lv, "#item-activities")
    refute has_element?(lv, "nav.tabs")
  end
end
