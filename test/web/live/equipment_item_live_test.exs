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

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/equipment/#{item.id}")

    assert has_element?(lv, "aside #item-fields h2.caps", "Equipment fields")
    assert has_element?(lv, "#item-fields-603", "Orange dry bag")
  end
end
