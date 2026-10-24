defmodule Web.MemberEquipmentLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), team: team, member: member_fixture(team)}
  end

  test "the tab lists every item, each kit's contents after it with where they are", ctx do
    %{team: team, member: member} = ctx
    kit = equipment_item_fixture(team, %{title: "First aid kit 6", member_id: member.id})

    pouch =
      equipment_item_fixture(team, %{
        title: "Splint pouch",
        d4h_container_id: kit.d4h_equipment_id,
        location_title: nil
      })

    splint =
      equipment_item_fixture(team, %{
        title: "SAM splint",
        d4h_container_id: pouch.d4h_equipment_id,
        location_title: nil
      })

    old =
      equipment_item_fixture(team, %{title: "Old radio", member_id: member.id, status: "retired"})

    gps = equipment_item_fixture(team, %{title: "GPS 5", member_id: member.id})
    # Another team's item with a matching container id isn't in the kit.
    equipment_item_fixture(team_fixture(), %{
      title: "Stray",
      d4h_container_id: kit.d4h_equipment_id
    })

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{team}/members/#{member.id}/equipment")

    ids = for item <- [kit, pouch, splint, gps, old], do: "member-equipment-list-#{item.id}"
    html = lv |> element("#member-equipment-list") |> render()

    shown = Regex.scan(~r/id="(member-equipment-list-\d+)"/, html, capture: :all_but_first)
    assert List.flatten(shown) == ids

    assert has_element?(
             lv,
             "#member-equipment-list-#{splint.id}",
             "First aid kit 6 › Splint pouch"
           )

    assert has_element?(
             lv,
             ~s{#member-equipment-list-#{gps.id} a[href="/teams/#{team.subdomain}/equipment/#{gps.id}"]}
           )

    assert has_element?(lv, "#member-equipment-list-#{old.id} .badge", "Retired")
    assert has_element?(lv, ~s{nav.tabs a[aria-current="page"]}, "Equipment")
    assert has_element?(lv, "th", "Where")
    assert has_element?(lv, "#member-equipment-link", "5 items")
    refute has_element?(lv, "td", "Stray")
  end

  test "Where goes when nothing is inside another item", ctx do
    equipment_item_fixture(ctx.team, %{title: "GPS 5", member_id: ctx.member.id})

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/members/#{ctx.member.id}/equipment")

    assert has_element?(lv, "#member-equipment-list td", "GPS 5")
    # The table's id is on its tbody; the tab has one table.
    refute has_element?(lv, "th", "Where")
  end

  test "a member who holds nothing gets the empty state", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/members/#{ctx.member.id}/equipment")

    assert has_element?(lv, "#no-member-equipment", "No equipment")
    assert has_element?(lv, ~s{nav.tabs a[aria-current="page"]}, "Equipment")
  end

  test "another team's member is not found", ctx do
    stranger = member_fixture(team_fixture())

    assert_raise Ecto.NoResultsError, fn ->
      live(ctx.conn, ~p"/teams/#{ctx.team}/members/#{stranger.id}/equipment")
    end
  end
end
