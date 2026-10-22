defmodule Web.EquipmentLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Activity
  alias App.Model.ChangeSet
  alias App.Model.EquipmentUsage
  alias App.Model.Template
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    truck = equipment_item_fixture(team, %{title: "SOUTH FRASER 2", item_type: "vehicle"})

    radio =
      equipment_item_fixture(team, %{title: "Radio 7", d4h_container_id: truck.d4h_equipment_id})

    phone = equipment_item_fixture(team, %{title: "Cell phone", location_title: "Costing"})
    %{conn: log_in_user(conn, user), team: team, truck: truck, radio: radio, phone: phone}
  end

  test "the equipment page opens on places and categories, then lists a place's items", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment")

    assert has_element?(lv, "#equipment-places-yard", "2")
    assert has_element?(lv, "#equipment-places-costing", "1")
    assert has_element?(lv, "#equipment-categories-radio", "3")
    refute has_element?(lv, "#item-#{ctx.radio.id}")

    lv |> element("#equipment-places-yard a") |> render_click()
    assert_patch(lv, ~p"/teams/#{ctx.team}/equipment?place=Yard")
    assert has_element?(lv, "#place-yard #item-#{ctx.radio.id}", "Radio 7")
    assert has_element?(lv, "#place-yard #item-#{ctx.radio.id}", "SOUTH FRASER 2")
    refute has_element?(lv, "#item-#{ctx.phone.id}")
  end

  test "the equipment page searches every place", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment?show=all")

    assert has_element?(lv, "#place-yard #item-#{ctx.radio.id}", "Radio 7")
    assert has_element?(lv, "#place-yard #item-#{ctx.radio.id}", "SOUTH FRASER 2")
    assert has_element?(lv, "#place-costing #item-#{ctx.phone.id}")

    lv |> form("#equipment-filter", form: %{q: "radio 7", show: "in-service"}) |> render_change()
    assert has_element?(lv, "#item-#{ctx.radio.id}")
    refute has_element?(lv, "#item-#{ctx.phone.id}")
  end

  test "the Place chip removes the place and keeps the search (#350)", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment?place=Yard&q=radio")

    assert has_element?(lv, "#equipment-filter .filter-menu.is-on", "Place")
    lv |> element(".filter-bar-chips a", "Yard") |> render_click()

    path = assert_patch(lv)
    assert path =~ "q=radio"
    refute path =~ "place="
    assert has_element?(lv, "#item-#{ctx.radio.id}")
  end

  test "a scanned barcode opens its item, and an unknown one says so", ctx do
    item = equipment_item_fixture(ctx.team, %{title: "Thermal camera 2", barcode: "SF0119"})
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment")

    lv |> element("#equipment-scanner") |> render_hook("scanned", %{"code" => "SF9999"})
    assert has_element?(lv, "#scan-message", "No item has the barcode SF9999.")

    lv |> element("#equipment-scanner") |> render_hook("scanned", %{"code" => " sf0119 "})
    assert_redirect(lv, ~p"/teams/#{ctx.team}/equipment/#{item.id}")
  end

  test "scanning on an activity adds each item once, and refuses retired ones", ctx do
    activity = activity_fixture(ctx.team, %{title: "Night search"})
    equipment_usage_fixture(activity, ctx.truck)
    camera = equipment_item_fixture(ctx.team, %{title: "Thermal camera 2", barcode: "SF0119"})
    equipment_item_fixture(ctx.team, %{title: "Old rope", barcode: "SF0001", status: "retired"})
    ctx.truck |> Ecto.Changeset.change(barcode: "TRUCK2") |> Repo.update!()

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/equipment")
    scan = &(lv |> element("#equipment-scanner") |> render_hook("scanned", %{"code" => &1}))

    scan.("sf0119")
    assert has_element?(lv, "#scan-message", "Added Thermal camera 2.")
    assert lv |> element("#hours-#{camera.id}") |> render() =~ ~s(value="2")

    scan.("SF0119")
    assert has_element?(lv, "#scan-message", "already in the list to add")

    scan.("TRUCK2")
    assert has_element?(lv, "#scan-message", "SOUTH FRASER 2 is already on this activity.")

    scan.("SF0001")
    assert has_element?(lv, "#scan-message", "Old rope cannot be added. It is retired.")

    lv |> element("#equipment-scanner") |> render_hook("scan_failed", %{})
    assert has_element?(lv, "#scan-failed")
  end

  test "an item's page lists what is inside it and its activities", ctx do
    activity = activity_fixture(ctx.team, %{title: "Night search"})
    equipment_usage_fixture(activity, ctx.truck)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment/#{ctx.truck.id}")

    assert has_element?(lv, "#item-contents", "Radio 7")
    assert has_element?(lv, "#item-usages", "Night search")
  end

  test "a template is added with its items and hours", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/new")

    lv |> form("#item-search-form", %{q: "radio"}) |> render_change()
    lv |> element("#item-add-#{ctx.radio.id}") |> render_click()
    lv |> form("#item-search-form", %{q: "south"}) |> render_change()
    lv |> element("#item-add-#{ctx.truck.id}") |> render_click()

    assert has_element?(lv, "#hours-#{ctx.radio.id}")
    refute has_element?(lv, "#hours-#{ctx.truck.id}")

    lv
    |> form("#template-form", template: %{title: "Truck 2"}, hours: %{"#{ctx.radio.id}" => "2.5"})
    |> render_submit()

    template = Template |> Repo.get_by!(team_id: ctx.team.id) |> Repo.preload(:template_items)
    assert template.title == "Truck 2"

    assert template.template_items |> Enum.map(&{&1.equipment_item_id, &1.minutes}) |> Enum.sort() ==
             Enum.sort([{ctx.radio.id, 150}, {ctx.truck.id, 0}])
  end

  test "a template gets tags from the team's tags", ctx do
    water = tag_fixture(ctx.team, "Flat Water")
    tag_fixture(ctx.team, "Medical")
    activity_fixture(ctx.team, %{tags: ["Flat Water"]})
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/new")

    # With no search, only tags the team's activities used.
    assert has_element?(lv, "#tag-most-used")
    assert has_element?(lv, "#tag-add-#{water.id}")
    refute has_element?(lv, "#tag-search-results", "Medical")

    lv |> form("#tag-search-form", %{tag_q: "flat"}) |> render_change()
    refute has_element?(lv, "#tag-search-results", "Medical")
    lv |> element("#tag-add-#{water.id}") |> render_click()
    assert has_element?(lv, "#template-tags #tag-#{water.id}", "Flat Water")
    refute has_element?(lv, "#tag-add-#{water.id}")

    lv |> form("#template-form", template: %{title: "Boat training"}) |> render_submit()

    template = Template |> Repo.get_by!(team_id: ctx.team.id) |> Repo.preload(template_tags: :tag)
    assert Enum.map(template.template_tags, & &1.tag.title) == ["Flat Water"]
  end

  test "a template's tags join the activity's tags in D4H", ctx do
    activity = activity_fixture(ctx.team)
    water = tag_fixture(ctx.team, "Flat Water")
    hours = tag_fixture(ctx.team, "Primary Hours")
    template = template_fixture(ctx.team, "Boat training", [], [water, hours])
    path = "/exercises/#{activity.d4h_activity_id}"
    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case {conn.method, String.ends_with?(conn.request_path, path)} do
        {"GET", true} ->
          Req.Test.json(conn, %{
            "id" => activity.d4h_activity_id,
            "tags" => [%{"resourceType" => "Tag", "id" => hours.d4h_tag_id}]
          })

        {"GET", false} ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        {"POST", _activity?} ->
          send(test_pid, {:d4h_write, conn.request_path, Jason.decode!(body)})
          Req.Test.json(conn, %{"id" => activity.d4h_activity_id})
      end
    end)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/templates")
    lv |> element("#add-template-#{template.id}") |> render_click()

    # The activity has Primary Hours already.
    assert has_element?(lv, "#template-tags #tag-#{water.id}")
    refute has_element?(lv, "#template-tags #tag-#{hours.id}")
    assert has_element?(lv, "#template-send", "Add to activity")

    lv |> form("#template-lines") |> render_submit()

    assert_received {:d4h_write, tags_path, %{"tagIds" => tag_ids}}
    assert String.ends_with?(tags_path, path <> "/tags")
    assert tag_ids == Enum.sort([hours.d4h_tag_id, water.d4h_tag_id])
    assert Repo.get!(Activity, activity.id).tags == ["Flat Water", "Primary Hours"]
    assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{activity.id}")
  end

  test "a template gets groups to invite", ctx do
    managers = group_fixture(ctx.team, %{title: "Search Managers"})
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/new")

    lv |> element("#group-add-#{managers.id}") |> render_click()
    assert has_element?(lv, "#template-groups #group-#{managers.id}", "Search Managers")
    refute has_element?(lv, "#group-add-#{managers.id}")

    lv |> form("#template-form", template: %{title: "Managers' training"}) |> render_submit()

    template =
      Template |> Repo.get_by!(team_id: ctx.team.id) |> Repo.preload(template_groups: :group)

    assert Enum.map(template.template_groups, & &1.group.title) == ["Search Managers"]
  end

  test "a template's groups are invited to the activity in D4H", ctx do
    activity = activity_fixture(ctx.team)
    managers = group_fixture(ctx.team, %{title: "Search Managers"})
    mike = member_fixture(ctx.team, %{name: "Mike"})
    signed_up = member_fixture(ctx.team, %{name: "Signed up"})
    retired = member_fixture(ctx.team, %{name: "Retired", d4h_status: "RETIRED"})
    for member <- [mike, signed_up, retired], do: group_member_fixture(managers, member)
    attendance_fixture(activity, signed_up, %{status: "requested"})
    template = template_fixture(ctx.team, "Managers' training", [], [], [managers])
    path = "/exercises/#{activity.d4h_activity_id}"
    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case {conn.method, String.ends_with?(conn.request_path, path)} do
        {"GET", true} ->
          Req.Test.json(conn, %{"id" => activity.d4h_activity_id, "published" => false})

        {"GET", false} ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        {"POST", _activity?} ->
          json = Jason.decode!(body)
          send(test_pid, {:d4h_write, json})

          Req.Test.json(conn, %{
            "id" => System.unique_integer([:positive]),
            "activity" => %{"resourceType" => "Exercise", "id" => json["activityId"]},
            "member" => %{"id" => json["memberId"]},
            "status" => json["status"],
            "startsAt" => json["startsAt"],
            "endsAt" => json["endsAt"]
          })
      end
    end)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/templates")
    lv |> element("#add-template-#{template.id}") |> render_click()
    assert has_element?(lv, "#template-groups #group-#{managers.id}", "Search Managers")
    assert has_element?(lv, "#template-send", "Add to activity")

    lv |> form("#template-lines") |> render_submit()

    # Only Mike: the signed-up member is on the activity, and the retired one isn't current.
    assert_received {:d4h_write, %{"memberId" => mike_id, "status" => "REQUESTED"}}
    assert mike_id == mike.d4h_member_id
    refute_received {:d4h_write, _json}

    assert %ChangeSet{source: :template} = Repo.get_by!(ChangeSet, activity_id: activity.id)
    assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{activity.id}")
  end

  test "a template's items go to D4H as usages on the activity", ctx do
    activity = activity_fixture(ctx.team)
    template = template_fixture(ctx.team, "Truck 2", [{ctx.truck, 0}, {ctx.radio, 90}])
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

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/templates")
    lv |> element("#add-template-#{template.id}") |> render_click()
    assert has_element?(lv, "#line-#{ctx.radio.id}")

    assert has_element?(lv, "#km-#{ctx.truck.id}")
    refute has_element?(lv, "#km-#{ctx.radio.id}")

    lv
    |> form("#template-lines",
      hours: %{"#{ctx.radio.id}" => "1"},
      km: %{"#{ctx.truck.id}" => "35"}
    )
    |> render_submit()

    assert_received {:d4h_write, %{"equipmentId" => truck_id} = truck_json}
    assert truck_id == ctx.truck.d4h_equipment_id
    refute Map.has_key?(truck_json, "duration")
    assert truck_json["distance"] == 35_000
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

  test "a D4H team cannot add or change items here", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment")
    refute has_element?(lv, "#equipment-add")

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment/#{ctx.truck.id}")
    refute has_element?(lv, "#item-edit")

    assert has_element?(
             lv,
             ~s(#item-actions a[href$="/team/equipment/view/#{ctx.truck.d4h_equipment_id}"]),
             "Open D4H item"
           )

    assert_error_sent 404, fn -> get(ctx.conn, ~p"/teams/#{ctx.team}/equipment/new") end
  end
end
