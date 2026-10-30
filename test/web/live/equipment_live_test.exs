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

    lv |> form("#equipment-filter", form: %{q: "radio 7"}) |> render_change()
    assert has_element?(lv, "#item-#{ctx.radio.id}")
    refute has_element?(lv, "#item-#{ctx.phone.id}")
  end

  test "Unserviceable and Lost are tiles of their own, and Expires filters across them",
       ctx do
    soon = DateTime.add(DateTime.utc_now(), 10, :day)
    broken = equipment_item_fixture(ctx.team, %{title: "Broken vest", status: "unserviceable"})

    gone =
      equipment_item_fixture(ctx.team, %{title: "Gone rope", status: "lost", expires_at: soon})

    due = equipment_item_fixture(ctx.team, %{title: "Due harness", expires_at: soon})

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment?show=all")

    # The setup's three, and the due harness.
    assert has_element?(lv, "#equipment-view-in-service", "4")
    assert has_element?(lv, "#equipment-view-unserviceable", "1")
    assert has_element?(lv, "#equipment-view-lost", "1")
    refute has_element?(lv, "#equipment-view-expiring")
    refute has_element?(lv, "#equipment-view-problems")

    # Mixed statuses: each row's badge says which.
    assert has_element?(lv, "#item-#{broken.id} .badge", "Unserviceable")

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment?show=lost")
    assert has_element?(lv, "#item-#{gone.id}", "Gone rope")
    refute has_element?(lv, "#item-#{gone.id} .badge", "Lost")
    refute has_element?(lv, "#item-#{broken.id}")

    # In service, the usual tile, with the Expires filter: what to renew.
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment?expires=soon")
    assert has_element?(lv, "#equipment-view-in-service", "1")
    assert has_element?(lv, "#equipment-view-lost", "1")
    assert has_element?(lv, "#item-#{due.id}")
    refute has_element?(lv, "#item-#{gone.id}")
  end

  test "the stat switch counts each part of the place and keeps the search", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment?place=Yard&q=radio")

    assert has_element?(lv, "#equipment-view-in-service[aria-current]", "2")
    assert has_element?(lv, "#equipment-view-retired", "0")

    lv |> element("#equipment-view-all") |> render_click()
    path = assert_patch(lv)
    assert path =~ "show=all"
    assert path =~ "q=radio"
    assert has_element?(lv, "#equipment-view-all[aria-current]")
  end

  test "the Where chip removes the place and keeps the search (#350)", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment?place=Yard&q=radio")

    assert has_element?(lv, "#equipment-filter .filter-menu.is-on", "Where")
    lv |> element(".filter-bar-chips a", "Yard") |> render_click()

    path = assert_patch(lv)
    assert path =~ "q=radio"
    refute path =~ "place="
    assert has_element?(lv, "#item-#{ctx.radio.id}")
  end

  test "Where takes a member: their items under their name, with no Where column (#490)", ctx do
    sam = member_fixture(ctx.team, %{name: "Sam Rivera"})
    gps = equipment_item_fixture(ctx.team, %{title: "GPS 5", member_id: sam.id})
    equipment_item_fixture(ctx.team, %{title: "Pager 31", member_id: sam.id})
    other = member_fixture(ctx.team, %{name: "Ty Wong"})
    equipment_item_fixture(ctx.team, %{title: "Radio 22", member_id: other.id})

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment?place=member-#{sam.id}")

    assert has_element?(
             lv,
             ~s{#form_place-select option[value="member-#{sam.id}"]},
             "With Sam Rivera"
           )

    assert has_element?(lv, ~s{#form_place-select option[value="With members"]})
    assert has_element?(lv, "#place-sam-rivera h2", "Sam Rivera · 2")
    assert has_element?(lv, "#equipment-sam-rivera-#{gps.id}", "GPS 5")
    refute has_element?(lv, "#place-sam-rivera th", "Where")
    refute has_element?(lv, "#place-with-members")
    refute has_element?(lv, "td", "Radio 22")
  end

  test "Where takes retiring members: a group for each who holds something (#514)", ctx do
    leavers = group_fixture(ctx.team, %{title: "Leavers"})

    team =
      ctx.team
      |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id)
      |> App.Repo.update!()

    sam = member_fixture(team, %{name: "Sam Rivera"})
    ty = member_fixture(team, %{name: "Ty Wong"})
    staying = member_fixture(team, %{name: "Al Staying"})
    for member <- [sam, ty], do: group_member_fixture(leavers, member)
    kit = equipment_item_fixture(team, %{title: "First aid kit 6", member_id: sam.id})

    splint =
      equipment_item_fixture(team, %{title: "Splint", d4h_container_id: kit.d4h_equipment_id})

    gps = equipment_item_fixture(team, %{title: "GPS 5", member_id: ty.id, status: "retired"})
    equipment_item_fixture(team, %{title: "Radio 22", member_id: staying.id})

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{team}/equipment?place=retiring")

    assert has_element?(
             lv,
             ~s{#form_place-select option[value="retiring"]},
             "With retiring members"
           )

    assert has_element?(lv, "#equipment-holders-member-#{sam.id} th", "Sam Rivera · 2")
    assert has_element?(lv, "#equipment-holders-member-#{sam.id} #item-#{splint.id}", "Splint")
    assert has_element?(lv, "#equipment-holders-member-#{ty.id} #item-#{gps.id}", "GPS 5")
    refute has_element?(lv, "td", "Radio 22")
  end

  test "With members is one table, a group per member (#514)", ctx do
    sam = member_fixture(ctx.team, %{name: "Sam Rivera"})
    gps = equipment_item_fixture(ctx.team, %{title: "GPS 5", member_id: sam.id})

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment?place=With+members")

    assert has_element?(lv, "#equipment-holders-member-#{sam.id} th", "Sam Rivera · 1")
    assert has_element?(lv, "#equipment-holders-member-#{sam.id} #item-#{gps.id}")
    refute has_element?(lv, "#item-#{ctx.radio.id}")
  end

  test "Where offers retiring members only with a Retiring group", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment")
    refute has_element?(lv, ~s{#form_place-select option[value="retiring"]})
  end

  test "the browse page keeps one With members row", ctx do
    for name <- ["Sam Rivera", "Ty Wong"] do
      member = member_fixture(ctx.team, %{name: name})
      equipment_item_fixture(ctx.team, %{member_id: member.id, location_title: nil})
    end

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment")

    assert has_element?(lv, "#equipment-places-with-members", "2")
    refute has_element?(lv, "#equipment-places tbody", "Sam Rivera")
  end

  test "a member of another team, or one who holds nothing, is an unknown place", ctx do
    other_team = team_fixture()
    stranger = member_fixture(other_team)
    equipment_item_fixture(other_team, %{title: "Their radio", member_id: stranger.id})
    idle = member_fixture(ctx.team)

    for member <- [stranger, idle] do
      {:ok, lv, _html} =
        live(ctx.conn, ~p"/teams/#{ctx.team}/equipment?place=member-#{member.id}")

      assert has_element?(lv, "#no-matching-equipment")
      refute has_element?(lv, ~s{#form_place-select option[value="member-#{member.id}"]})
    end
  end

  test "the Equipment tab and Equipment count a kit's contents alike", ctx do
    sam = member_fixture(ctx.team, %{name: "Sam Rivera"})
    kit = equipment_item_fixture(ctx.team, %{title: "First aid kit 6", member_id: sam.id})

    pouch =
      equipment_item_fixture(ctx.team, %{
        title: "Pouch",
        d4h_container_id: kit.d4h_equipment_id,
        location_title: nil
      })

    splint =
      equipment_item_fixture(ctx.team, %{
        title: "Splint",
        d4h_container_id: pouch.d4h_equipment_id,
        location_title: nil
      })

    equipment_item_fixture(ctx.team, %{
      title: "Old gauze",
      status: "retired",
      d4h_container_id: kit.d4h_equipment_id
    })

    for n <- 1..4,
        do: equipment_item_fixture(ctx.team, %{title: "Radio #{n}", member_id: sam.id})

    # Another team's item with the same container id isn't in Sam's kit.
    equipment_item_fixture(team_fixture(), %{
      title: "Stray",
      d4h_container_id: kit.d4h_equipment_id
    })

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/members/#{sam.id}/equipment")
    html = lv |> element("#member-equipment-list") |> render()
    assert length(Regex.scan(~r/<tr /, html)) == 8
    assert has_element?(lv, "#member-equipment-list-#{pouch.id}", "First aid kit 6")
    refute has_element?(lv, "td", "Stray")

    # A member place opens on All, so it counts the retired gauze as the tab does.
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment?place=member-#{sam.id}")
    assert has_element?(lv, "#place-sam-rivera h2", "Sam Rivera · 8")
    assert has_element?(lv, "#equipment-view-all[aria-current]", "8")
    assert has_element?(lv, "#equipment-view-in-service", "7")
    assert has_element?(lv, "#equipment-view-retired", "1")
    assert has_element?(lv, "td", "Old gauze")
    refute has_element?(lv, "td", "Stray")

    # Where says what each item is inside, without the name the heading already gives.
    assert has_element?(lv, "#place-sam-rivera th", "Where")
    assert has_element?(lv, "#equipment-sam-rivera-#{splint.id}", "First aid kit 6 › Pouch")
    refute has_element?(lv, "#equipment-sam-rivera-#{splint.id}", "Sam Rivera")

    # In service still filters here, and a place picked after it keeps it.
    lv |> element("#equipment-view-in-service") |> render_click()
    assert assert_patch(lv) =~ "show=in-service"
    assert has_element?(lv, "#place-sam-rivera h2", "Sam Rivera · 7")
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

    {:ok, lv, _html} =
      live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/equipment/add")

    scan = &(lv |> element("#equipment-scanner") |> render_hook("scanned", %{"code" => &1}))

    scan.("sf0119")
    assert has_element?(lv, "#scan-message", "Added Thermal camera 2.")
    assert lv |> element("#hours-#{camera.id}") |> render() =~ ~s(value="2")

    assert has_element?(
             lv,
             ~s|#equipment-cancel[href="#{~p"/teams/#{ctx.team}/activities/#{activity.id}"}"]|
           )

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

  test "a template is added with a name and kind, then lands on its page", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/new")
    assert has_element?(lv, ~s|#template-cancel[href="#{~p"/teams/#{ctx.team}/templates"}"]|)
    refute has_element?(lv, "#item-search-form")

    {:ok, _lv, html} =
      lv
      |> form("#template-form", template: %{title: "Truck 2", activity_kind: "exercise"})
      |> render_submit()
      |> follow_redirect(ctx.conn)

    assert html =~ "Saved the Truck 2 template."
    template = Repo.get_by!(Template, team_id: ctx.team.id)
    assert {template.title, template.activity_kind} == {"Truck 2", "exercise"}
  end

  test "Change items saves a template's items and hours", ctx do
    template = template_fixture(ctx.team, "Truck 2")
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/#{template.id}/items/edit")
    assert has_element?(lv, "h1", "Change items for Truck 2")

    lv |> form("#item-search-form", %{q: "radio"}) |> render_change()
    lv |> element("#item-add-#{ctx.radio.id}") |> render_click()
    lv |> form("#item-search-form", %{q: "south"}) |> render_change()
    lv |> element("#item-add-#{ctx.truck.id}") |> render_click()

    assert has_element?(lv, "#hours-#{ctx.radio.id}")
    refute has_element?(lv, "#hours-#{ctx.truck.id}")

    lv |> form("#template-form", hours: %{"#{ctx.radio.id}" => "2.5"}) |> render_submit()
    assert_redirect(lv, ~p"/teams/#{ctx.team}/templates/#{template.id}")

    template = Template |> Repo.get!(template.id) |> Repo.preload(:template_items)
    assert template.title == "Truck 2"

    assert template.template_items |> Enum.map(&{&1.equipment_item_id, &1.minutes}) |> Enum.sort() ==
             Enum.sort([{ctx.radio.id, 150}, {ctx.truck.id, 0}])
  end

  test "a template gets tags from the team's tags", ctx do
    water = tag_fixture(ctx.team, "Flat Water")
    tag_fixture(ctx.team, "Medical")
    activity_fixture(ctx.team, %{tags: ["Flat Water"]})
    template = template_fixture(ctx.team, "Boat training")
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/#{template.id}/tags/edit")

    # With no search, only tags the team's activities used.
    assert has_element?(lv, "#tag-most-used")
    assert has_element?(lv, "#tag-add-#{water.id}")
    refute has_element?(lv, "#tag-search-results", "Medical")

    lv |> form("#tag-search-form", %{tag_q: "flat"}) |> render_change()
    refute has_element?(lv, "#tag-search-results", "Medical")
    lv |> element("#tag-add-#{water.id}") |> render_click()
    assert has_element?(lv, "#template-tags #tag-#{water.id}", "Flat Water")
    refute has_element?(lv, "#tag-add-#{water.id}")

    lv |> form("#template-form") |> render_submit()

    template = Template |> Repo.get!(template.id) |> Repo.preload(template_tags: :tag)
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

    assert has_element?(
             lv,
             ~s|#template-cancel[href="#{~p"/teams/#{ctx.team}/activities/#{activity.id}"}"]|
           )

    lv |> form("#template-lines") |> render_submit()

    assert_received {:d4h_write, tags_path, %{"tagIds" => tag_ids}}
    assert String.ends_with?(tags_path, path <> "/tags")
    assert tag_ids == Enum.sort([hours.d4h_tag_id, water.d4h_tag_id])
    assert Repo.get!(Activity, activity.id).tags == ["Flat Water", "Primary Hours"]
    assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{activity.id}")
  end

  test "a template gets groups whose members it adds", ctx do
    managers = group_fixture(ctx.team, %{title: "Search Managers"})
    template = template_fixture(ctx.team, "Managers' training")
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/#{template.id}/groups/edit")

    lv |> element("#group-add-#{managers.id}") |> render_click()
    assert has_element?(lv, "#template-groups #group-#{managers.id}", "Search Managers")
    refute has_element?(lv, "#group-add-#{managers.id}")

    lv |> form("#template-form") |> render_submit()

    template = Template |> Repo.get!(template.id) |> Repo.preload(template_groups: :group)

    assert Enum.map(template.template_groups, & &1.group.title) == ["Search Managers"]
  end

  test "a template's groups' members are added to the activity in D4H", ctx do
    starts = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)
    activity = activity_fixture(ctx.team, %{started_at: starts})
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
    flash = assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{activity.id}")
    assert flash["info"] == "1 member added."

    # The copy has Mike at once, as No reply.
    assert Repo.get_by!(App.Model.Attendance, activity_id: activity.id, member_id: mike.id).status ==
             "requested"
  end

  defp cause_field(team) do
    custom_field_fixture(team, %{
      title: "Primary Cause",
      field_type: "single_choice",
      options: [
        %{"id" => 1, "label" => "Lost", "ordering" => 0, "archived" => false},
        %{"id" => 2, "label" => "Injured", "ordering" => 1, "archived" => false}
      ]
    })
  end

  defp incident_template(team, title, items, values) do
    template = template_fixture(team, title, items)
    changes = [activity_kind: "incident", custom_values: values]
    template |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  test "Change fields shows the kind's fields and saves the filled ones", ctx do
    cause = cause_field(ctx.team)
    custom_field_fixture(ctx.team, %{target: "event", title: "Event Leader"})
    template = incident_template(ctx.team, "Lost hiker", [], %{})
    path = ~p"/teams/#{ctx.team}/templates/#{template.id}/fields/edit"
    {:ok, lv, _html} = live(ctx.conn, path)

    assert has_element?(lv, "#custom-field-#{cause.d4h_custom_field_id}")
    refute has_element?(lv, "#template-fields", "Event Leader")

    lv
    |> form("#template-form", fields: %{"#{cause.d4h_custom_field_id}" => "1"})
    |> render_submit()

    template = Repo.get!(Template, template.id)
    assert template.custom_values == %{"#{cause.d4h_custom_field_id}" => [1]}

    {:ok, _lv, html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates")
    assert html =~ "Incident"
  end

  test "a template for any kind has no fields, and a new kind drops the old values", ctx do
    cause = cause_field(ctx.team)
    template = template_fixture(ctx.team, "Truck 1")
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/#{template.id}")
    refute has_element?(lv, "#template-edit-fields")

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/#{template.id}/fields/edit")
    assert has_element?(lv, "#template-no-fields", "for any kind")
    refute has_element?(lv, "#template-save")

    values = %{"#{cause.d4h_custom_field_id}" => [1]}
    template = incident_template(ctx.team, "Lost hiker", [], values)
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/#{template.id}/edit")
    assert has_element?(lv, "#template-form", "A new kind drops the 1 field value.")

    lv |> form("#template-form", template: %{activity_kind: "exercise"}) |> render_submit()
    assert Repo.get!(Template, template.id).custom_values == %{}
  end

  test "a template's page shows what it adds, and deletes it from its Actions", ctx do
    cause = cause_field(ctx.team)
    values = %{"#{cause.d4h_custom_field_id}" => [2]}
    template = incident_template(ctx.team, "Lost hiker", [{ctx.radio, 90}], values)
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/#{template.id}")

    assert has_element?(lv, "#template-details", "Incident")
    assert has_element?(lv, "#template-items-table", "Radio 7")
    assert has_element?(lv, "#template-items-table", "1h 30m")
    assert has_element?(lv, "#template-fields-#{cause.d4h_custom_field_id}", "Injured")

    assert has_element?(
             lv,
             ~s|#template-edit[href="#{~p"/teams/#{ctx.team}/templates/#{template.id}/edit"}"]|
           )

    assert has_element?(lv, "#template-edit-items")
    assert has_element?(lv, "#template-edit-fields")
    assert has_element?(lv, "#template-delete[data-confirm-button='Delete template']")

    {:ok, _lv, html} =
      lv
      |> element("#template-delete")
      |> render_click()
      |> follow_redirect(ctx.conn, ~p"/teams/#{ctx.team}/templates")

    assert html =~ "Deleted the Lost hiker template."
    refute Repo.get(Template, template.id)
  end

  test "Change template has no Delete, and Cancel goes back to the template", ctx do
    template = template_fixture(ctx.team, "Truck 1")
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/templates/#{template.id}/edit")

    assert has_element?(lv, "h1", "Change Truck 1")
    refute has_element?(lv, "#template-delete")

    assert has_element?(
             lv,
             ~s|#template-cancel[href="#{~p"/teams/#{ctx.team}/templates/#{template.id}"}"]|
           )
  end

  test "a template fills in the incident's empty fields in D4H", ctx do
    cause = cause_field(ctx.team)
    agency = custom_field_fixture(ctx.team, %{title: "Requesting Agency"})
    cause_id = "#{cause.d4h_custom_field_id}"
    agency_id = "#{agency.d4h_custom_field_id}"

    activity =
      activity_fixture(ctx.team, %{
        activity_kind: "incident",
        custom_values: %{agency_id => "Surrey RCMP"}
      })

    template =
      incident_template(ctx.team, "Lost hiker", [], %{cause_id => [1], agency_id => "RCMP"})

    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.method do
        "GET" ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        method ->
          send(test_pid, {:d4h_write, method, conn.request_path, Jason.decode!(body)})

          Req.Test.json(
            conn,
            App.RecordsStub.activity_json(activity.d4h_activity_id, %{
              "resourceType" => "Incident"
            })
          )
      end
    end)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/templates")
    assert has_element?(lv, "#template-#{template.id}", "Incident: 0 items, 2 fields")
    lv |> element("#add-template-#{template.id}") |> render_click()

    # The agency is filled in already, so only the cause goes.
    assert has_element?(lv, "#template-fields #field-#{cause_id}", "Lost")
    refute has_element?(lv, "#template-fields #field-#{agency_id}")

    lv |> form("#template-lines") |> render_submit()

    assert_received {:d4h_write, "PATCH", path, body}
    assert String.ends_with?(path, "/incidents/#{activity.d4h_activity_id}")

    assert body == %{
             "customFieldValues" => [%{"id" => cause.d4h_custom_field_id, "value" => [1]}]
           }

    refute_received {:d4h_write, _method, _path, _body}

    flash = assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{activity.id}")
    assert flash["info"] == "1 field filled in."

    assert Repo.get!(Activity, activity.id).custom_values == %{
             cause_id => [1],
             agency_id => "Surrey RCMP"
           }
  end

  test "when the tags fail after the fields went, the page leaves and says the fields went",
       ctx do
    cause = cause_field(ctx.team)
    water = tag_fixture(ctx.team, "Flat Water")
    activity = activity_fixture(ctx.team, %{activity_kind: "incident"})
    values = %{"#{cause.d4h_custom_field_id}" => [1]}

    template =
      ctx.team
      |> template_fixture("Lost hiker", [], [water])
      |> Ecto.Changeset.change(activity_kind: "incident", custom_values: values)
      |> Repo.update!()

    patched = :atomics.new(1, [])

    # D4H takes the fields, then refuses the read before the tags.
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      case {conn.method, :atomics.get(patched, 1)} do
        {"GET", 0} ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        {"GET", _patched} ->
          conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"message" => "Refused"})

        {"PATCH", _patched} ->
          :atomics.put(patched, 1, 1)

          Req.Test.json(
            conn,
            App.RecordsStub.activity_json(activity.d4h_activity_id, %{
              "resourceType" => "Incident"
            })
          )
      end
    end)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/templates")
    lv |> element("#add-template-#{template.id}") |> render_click()
    lv |> form("#template-lines") |> render_submit()

    flash = assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{activity.id}")
    assert flash["error"] =~ ~r/^1 field filled in\. The change was not sent\./
  end

  test "a published activity's fields are left out", ctx do
    cause = cause_field(ctx.team)
    activity = activity_fixture(ctx.team, %{activity_kind: "incident", is_published: true})

    values = %{"#{cause.d4h_custom_field_id}" => [1]}
    template = incident_template(ctx.team, "Lost hiker", [{ctx.radio, 60}], values)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/templates")
    lv |> element("#add-template-#{template.id}") |> render_click()

    refute has_element?(lv, "#template-fields")
    assert has_element?(lv, "#template-fields-locked", "the activity is published")
    assert has_element?(lv, "#template-lines-table")
  end

  # A template still logs a truck's hours after an activity, but adds nobody.
  test "after the start, a template's items go and its groups are left out", ctx do
    activity = activity_fixture(ctx.team)
    managers = group_fixture(ctx.team, %{title: "Search Managers"})
    group_member_fixture(managers, member_fixture(ctx.team))
    template = template_fixture(ctx.team, "Command response", [{ctx.radio, 90}], [], [managers])
    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.method do
        "GET" ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        "POST" ->
          json = Jason.decode!(body)
          send(test_pid, {:d4h_write, json})
          Req.Test.json(conn, %{"id" => System.unique_integer([:positive])})
      end
    end)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/templates")
    lv |> element("#add-template-#{template.id}") |> render_click()
    lv |> form("#template-lines") |> render_submit()

    assert_received {:d4h_write, %{"equipmentId" => _}}
    refute_received {:d4h_write, %{"status" => "REQUESTED"}}
    flash = assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{activity.id}")
    assert flash["info"] == "1 item added. Its groups were left out: the activity has started."
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

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/equipment")
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

    {:ok, lv, _html} =
      live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/equipment/add")

    lv |> element("#equipment-add-last") |> render_click()

    assert lv |> element("#hours-#{ctx.phone.id}") |> render() =~ ~s(value="1")
    assert length(Repo.all(EquipmentUsage)) == 1
  end

  test "a D4H team cannot add or delete items here", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment")
    refute has_element?(lv, "#equipment-add")

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/equipment/#{ctx.truck.id}")
    refute has_element?(lv, "#item-delete")

    assert has_element?(
             lv,
             ~s(#item-actions a[href$="/team/equipment/view/#{ctx.truck.d4h_equipment_id}"]),
             "Open in D4H"
           )

    assert_error_sent 404, fn -> get(ctx.conn, ~p"/teams/#{ctx.team}/equipment/new") end
  end
end
