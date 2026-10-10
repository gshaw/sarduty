defmodule Web.EquipmentLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.Model.EquipmentUsage
  alias App.Model.Kit
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    truck = equipment_item_fixture(team, %{title: "SOUTH FRASER 2", item_type: "vehicle"})

    radio =
      equipment_item_fixture(team, %{title: "Radio 7", d4h_container_id: truck.d4h_equipment_id})

    phone = equipment_item_fixture(team, %{title: "Cell phone", location_title: "Costing"})
    %{conn: log_in_user(conn, user), team: team, truck: truck, radio: radio, phone: phone}
  end

  test "the equipment page groups items by place, and searches", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment")

    assert has_element?(lv, "#place-yard #item-#{ctx.radio.id}", "Radio 7")
    assert has_element?(lv, "#place-yard #item-#{ctx.radio.id}", "SOUTH FRASER 2")
    assert has_element?(lv, "#place-costing #item-#{ctx.phone.id}")

    lv |> form("#equipment-filter", form: %{q: "radio 7", show: "in-service"}) |> render_change()
    assert has_element?(lv, "#item-#{ctx.radio.id}")
    refute has_element?(lv, "#item-#{ctx.phone.id}")
  end

  test "an item's page lists what is inside it and its activities", ctx do
    activity = activity_fixture(ctx.team, %{title: "Night search"})
    equipment_usage_fixture(activity, ctx.truck)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment/#{ctx.truck.id}")

    assert has_element?(lv, "#item-contents", "Radio 7")
    assert has_element?(lv, "#item-usages", "Night search")
  end

  test "a kit is added with its items and hours", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment/kits/new")

    lv |> form("#item-search-form", %{q: "radio"}) |> render_change()
    lv |> element("#item-add-#{ctx.radio.id}") |> render_click()
    lv |> form("#item-search-form", %{q: "south"}) |> render_change()
    lv |> element("#item-add-#{ctx.truck.id}") |> render_click()

    assert has_element?(lv, "#hours-#{ctx.radio.id}")
    refute has_element?(lv, "#hours-#{ctx.truck.id}")

    lv
    |> form("#kit-form", kit: %{title: "Truck 2"}, hours: %{"#{ctx.radio.id}" => "2.5"})
    |> render_submit()

    kit = Kit |> Repo.get_by!(team_id: ctx.team.id) |> Repo.preload(:kit_items)
    assert kit.title == "Truck 2"

    assert kit.kit_items |> Enum.map(&{&1.equipment_item_id, &1.minutes}) |> Enum.sort() ==
             Enum.sort([{ctx.radio.id, 150}, {ctx.truck.id, 0}])
  end

  test "a kit's items go to D4H as usages on the activity", ctx do
    activity = activity_fixture(ctx.team)
    kit = kit_fixture(ctx.team, "Truck 2", [{ctx.truck, 0}, {ctx.radio, 90}])
    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.method do
        "GET" ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        "POST" ->
          json = Jason.decode!(body)
          send(test_pid, {:d4h_write, json})

          Req.Test.json(conn, %{
            "id" => System.unique_integer([:positive]),
            "activity" => %{"resourceType" => "Exercise", "id" => json["activityId"]},
            "equipment" => %{"id" => json["equipmentId"]}
          })
      end
    end)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/equipment")
    lv |> element("#equipment-add-kit-#{kit.id}") |> render_click()
    assert has_element?(lv, "#line-#{ctx.radio.id}")

    lv |> form("#equipment-lines", hours: %{"#{ctx.radio.id}" => "1"}) |> render_submit()

    assert_received {:d4h_write, %{"equipmentId" => truck_id} = truck_json}
    assert truck_id == ctx.truck.d4h_equipment_id
    refute Map.has_key?(truck_json, "duration")
    assert_received {:d4h_write, %{"equipmentId" => radio_id, "duration" => 60}}
    assert radio_id == ctx.radio.d4h_equipment_id

    assert %ChangeSet{source: :equipment} = Repo.get_by!(ChangeSet, activity_id: activity.id)
    assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{activity.id}")
  end

  test "the activity page shows its equipment", ctx do
    activity = activity_fixture(ctx.team)
    equipment_usage_fixture(activity, ctx.radio)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}")
    assert has_element?(lv, "#activity-equipment-table", "Radio 7")
    assert has_element?(lv, "#activity-equipment-add")
  end

  test "same as last copies the previous activity's items", ctx do
    earlier =
      activity_fixture(ctx.team, %{
        started_at: ~U[2026-09-01 10:00:00Z],
        finished_at: ~U[2026-09-01 12:00:00Z]
      })

    equipment_usage_fixture(earlier, ctx.phone, %{minutes: 60})
    activity = activity_fixture(ctx.team)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/equipment")
    lv |> element("#equipment-add-last") |> render_click()

    assert lv |> element("#hours-#{ctx.phone.id}") |> render() =~ ~s(value="1")
    assert length(Repo.all(EquipmentUsage)) == 1
  end

  test "a team on SAR Duty Records has no equipment pages", %{conn: conn} do
    %{user: user, team: team} = records_team_with_user_fixture()
    conn = log_in_user(conn, user)

    assert_error_sent 404, fn -> get(conn, ~p"/teams/#{team}/equipment") end
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity_fixture(team).id}")
    refute has_element?(lv, "#activity-equipment")
  end
end
