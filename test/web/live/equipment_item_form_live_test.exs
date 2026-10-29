defmodule Web.EquipmentItemFormLiveTest do
  # Equipment items of a team on SAR Duty Records (#271, docs/records.md).
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSetRow
  alias App.RecordsStub
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
    %{conn: log_in_user(conn, user), team: team}
  end

  defp stub, do: RecordsStub.stub(&reply/3)

  defp reply("POST", "/equipment-locations", body), do: {200, Map.put(body, "id", 5)}

  defp reply("DELETE", "/equipment/" <> _id, _body), do: {200, %{}}

  defp reply(_method, _path, body),
    do: {200, Map.merge(%{"id" => 99, "ref" => "RESCUE 1", "type" => "VEHICLE"}, body || %{})}

  test "an item is added in a new place", %{conn: conn, team: team} do
    stub()
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/equipment")
    assert has_element?(list, "#equipment-add")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/equipment/new")
    assert has_element?(lv, ~s|#equipment-item-cancel[href="#{~p"/teams/#{team}/equipment"}"]|)

    lv
    |> form("#equipment-item-form", form: %{place: "new"})
    |> render_change()

    lv
    |> form("#equipment-item-form",
      form: %{
        title: "RESCUE 1",
        item_type: "vehicle",
        place: "new",
        new_place: "Hall",
        barcode: "R1",
        expires_on: "2027-01-01"
      }
    )
    |> render_submit()

    assert_received {:records, "POST", "/equipment-locations", %{"title" => "Hall"}}

    assert_received {:records, "POST", "/equipment", body}

    assert body == %{
             "ref" => "RESCUE 1",
             "type" => "VEHICLE",
             "status" => "OPERATIONAL",
             "barcode" => "R1",
             "serial" => nil,
             "location" => %{"resourceType" => "EquipmentLocation", "id" => 5},
             "dateExpires" => "2027-01-01T07:00:00Z"
           }
  end

  test "a name is needed, and a new place needs its name", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/equipment/new")
    lv |> form("#equipment-item-form", form: %{place: "new"}) |> render_change()

    html =
      lv
      |> form("#equipment-item-form", form: %{title: "", place: "new", new_place: ""})
      |> render_submit()

    assert html =~ "Enter a name."
    assert html =~ "Enter the new place."
  end

  test "a change sends only what changed, and an item cannot go inside itself",
       %{conn: conn, team: team} do
    stub()
    truck = equipment_item_fixture(team, %{title: "RESCUE 1", d4h_equipment_id: 10})

    drawer =
      equipment_item_fixture(team, %{title: "Drawer", d4h_equipment_id: 11, d4h_container_id: 10})

    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/equipment/#{drawer.id}")
    assert has_element?(page, "#item-actions #item-edit", "Change item")
    assert has_element?(page, "#item-actions #item-delete", "Delete item")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/equipment/#{truck.id}/edit")

    assert has_element?(
             lv,
             ~s|#equipment-item-cancel[href="#{~p"/teams/#{team}/equipment/#{truck.id}"}"]|
           )

    refute has_element?(lv, ~s(#form_place option[value="Equipment:11"]))
    refute has_element?(lv, ~s(#form_place option[value="Equipment:10"]))

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/equipment/#{drawer.id}/edit")
    assert has_element?(lv, ~s(#form_place option[value="Equipment:10"][selected]))

    lv
    |> form("#equipment-item-form", form: %{status: "lost", place: "Team"})
    |> render_submit()

    assert_received {:records, "PATCH", "/equipment/11", body}

    assert body == %{
             "status" => "LOST",
             "location" => %{"resourceType" => "Team", "id" => team.d4h_team_id}
           }
  end

  test "an item is deleted", %{conn: conn, team: team} do
    stub()
    item = equipment_item_fixture(team, %{d4h_equipment_id: 12})

    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/equipment/#{item.id}")
    link = page |> element("#item-delete") |> render()
    assert link =~ ~s(data-confirm-button="Delete item")
    # The dialog's button is red though the link isn't a red button.
    assert link =~ "data-confirm-danger"
    page |> element("#item-delete") |> render_click()
    assert_received {:records, "DELETE", "/equipment/12", nil}
  end

  test "a Records team's activity has an equipment section", %{conn: conn, team: team} do
    {:ok, lv, _html} =
      live(conn, ~p"/teams/#{team}/activities/#{activity_fixture(team).id}/equipment")

    assert has_element?(lv, "#activity-equipment-add")
  end

  describe "on a D4H team" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "d4h_key"}})
      %{conn: log_in_user(conn, user), team: team}
    end

    test "adding 404s, and Change item has only status and barcode",
         %{conn: conn, team: team} do
      item = equipment_item_fixture(team, %{d4h_equipment_id: 20})
      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/equipment/new") end

      {:ok, page, _html} = live(conn, ~p"/teams/#{team}/equipment/#{item.id}")
      assert has_element?(page, "#item-actions #item-edit", "Change item")
      refute has_element?(page, "#item-actions #item-delete")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/equipment/#{item.id}/edit")
      assert has_element?(lv, "#form_status")
      assert has_element?(lv, "#form_barcode")
      refute has_element?(lv, ~s(#form_status option[value="retired"]))
      refute has_element?(lv, "#form_title")
      refute has_element?(lv, "#form_place")
      refute has_element?(lv, "#form_serial")
      refute has_element?(lv, "#form_expires_on")
      assert has_element?(lv, "#equipment-item-elsewhere", "change in D4H")
    end

    test "saving sends D4H only the status and barcode that changed",
         %{conn: conn, team: team} do
      stub()
      item = equipment_item_fixture(team, %{d4h_equipment_id: 21, barcode: "OLD"})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/equipment/#{item.id}/edit")

      lv
      |> form("#equipment-item-form", form: %{status: "unserviceable", barcode: "NEW"})
      |> render_submit()

      assert_received {:records, "PATCH", "/equipment/21", body}
      assert body == %{"status" => "UNSERVICEABLE", "barcode" => "NEW"}

      [row] = Repo.all(ChangeSetRow)
      assert {row.action, row.status} == {:update_equipment_item, :applied}
    end

    test "a retired item's status stays as D4H has it", %{conn: conn, team: team} do
      stub()
      item = equipment_item_fixture(team, %{d4h_equipment_id: 22, status: "retired"})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/equipment/#{item.id}/edit")
      refute has_element?(lv, "#form_status")

      lv |> form("#equipment-item-form", form: %{barcode: "R9"}) |> render_submit()

      assert_received {:records, "PATCH", "/equipment/22", body}
      assert body == %{"barcode" => "R9"}
    end
  end
end
