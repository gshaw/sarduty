defmodule Web.MeDetailsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Adapter.D4H
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Repo
  alias App.ViewData.ChangeHistory

  setup %{conn: conn} do
    %{team: team, member: member, user: user} =
      member_with_login_fixture(%{
        address: "1 Main St",
        primary_emergency_contact: %{
          "name" => "Sam Rivera",
          "relation" => "Partner",
          "primary_phone" => "604-555-0100",
          "secondary_phone" => nil
        }
      })

    team = team |> Ecto.Changeset.change(d4h_access_key: "key") |> Repo.update!()
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  defp d4h_member(team, member, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => member.d4h_member_id,
        "name" => member.name,
        "owner" => %{"resourceType" => "Team", "id" => team.d4h_team_id},
        "email" => %{"value" => member.email},
        "mobile" => %{"phone" => nil},
        "deprecatedAddress" => "1 Main St",
        "primaryEmergencyContact" => %{
          "name" => "Sam Rivera",
          "relation" => "Partner",
          "primaryPhone" => "604-555-0100",
          "secondaryPhone" => ""
        },
        "secondaryEmergencyContact" => nil
      },
      overrides
    )
  end

  # Each PATCH body comes to the test process. The page reads the copy, so a GET fails
  # the test.
  defp stub_d4h(team, member) do
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn %{method: "PATCH"} = conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:patch, conn.request_path, Jason.decode!(body)})
      Req.Test.json(conn, d4h_member(team, member))
    end)
  end

  test "shows the member's copy, with no D4H read", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    assert has_element?(lv, "#details_contact1_name[value='Sam Rivera']")
    assert has_element?(lv, "#details_address", "1 Main St")
  end

  test "saves a change straight to D4H as the member's change set",
       %{conn: conn, team: team, member: member, user: user} do
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    lv
    |> form("#details-form",
      details: %{address: "2 Oak Ave", contact1_primary_phone: "604-555-0199"}
    )
    |> render_submit()

    assert_redirect(lv, ~p"/teams/#{team}/me/details")

    path = "/v3/team/#{team.d4h_team_id}/members/#{member.d4h_member_id}"
    assert_received {:patch, ^path, body}
    assert body["deprecatedAddress"] == "2 Oak Ave"
    assert body["primaryEmergencyContact"]["primaryPhone"] == "604-555-0199"
    assert body["primaryEmergencyContact"]["name"] == "Sam Rivera"
    refute Map.has_key?(body, "secondaryEmergencyContact")

    [change_set] = Repo.all(ChangeSet)
    assert {change_set.source, change_set.proposed_by_user_id} == {:member, user.id}
    [row] = Repo.all(ChangeSetRow)
    assert {row.status, row.member_id} == {:applied, member.id}
    member = Repo.reload!(member)
    assert member.address == "2 Oak Ave"
    assert member.primary_emergency_contact["primary_phone"] == "604-555-0199"
  end

  test "an unchanged form sends nothing", %{conn: conn, team: team, member: member} do
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    lv |> form("#details-form") |> render_submit()

    assert_redirect(lv, ~p"/teams/#{team}/me/details")
    refute_received {:patch, _path, _body}
    assert Repo.all(ChangeSet) == []
  end

  test "a team on SAR Duty Records changes emergency contacts too", %{conn: conn, member: member} do
    team =
      member.team
      |> Ecto.Changeset.change(d4h_api_host: D4H.records_host())
      |> Repo.update!()

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    assert has_element?(lv, "#details_address")
    assert has_element?(lv, "#details_contact1_name[value='Sam Rivera']")
  end

  test "a team admin page is still a 404 for the member", %{
    conn: conn,
    team: team,
    member: member
  } do
    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")
    end
  end

  test "invitation reminders are in account settings, not here",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")
    refute has_element?(lv, "[id^=invitation-reminders]")
  end

  # Radio Call Sign is editable, Year of birth viewable and restricted, Heritage restricted
  # and hidden, and Category hidden.
  defp member_fields(team, member) do
    custom_field_fixture(team, %{
      d4h_custom_field_id: 630,
      target: "member",
      title: "Radio Call Sign",
      member_privacy: "editable"
    })

    custom_field_fixture(team, %{
      d4h_custom_field_id: 855,
      target: "member",
      title: "Year of birth",
      restricted: true,
      member_privacy: "viewable"
    })

    custom_field_fixture(team, %{
      d4h_custom_field_id: 856,
      target: "member",
      title: "Heritage",
      restricted: true,
      member_privacy: "hidden"
    })

    custom_field_fixture(team, %{
      d4h_custom_field_id: 1361,
      target: "member",
      title: "Category",
      member_privacy: "hidden"
    })

    member
    |> Ecto.Changeset.change(
      custom_values: %{"630" => "SF 12", "1361" => [5], "855" => "1988", "856" => "Irish"}
    )
    |> Repo.update!()
  end

  test "a field to change is an input, one to see is read only, a hidden one never shows", %{
    conn: conn,
    team: team,
    member: member
  } do
    member_fields(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    assert has_element?(lv, "#details-form #custom-field-630[value='SF 12']")
    refute has_element?(lv, "#own-fields-630")
    assert has_element?(lv, "#details-form #own-fields-855", "1988")
    refute has_element?(lv, "#custom-field-855")
    refute has_element?(lv, "#own-fields-1361")
    refute has_element?(lv, "#custom-field-1361")
    refute has_element?(lv, "#own-fields-856")
    refute render(lv) =~ "Irish"
  end

  test "Save details sends a changed field on the details' row, and history names no value",
       %{conn: conn, team: team, member: member} do
    member = member_fields(team, member)
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    lv
    |> form("#details-form", details: %{address: "2 Oak Ave"}, fields: %{"630" => "SF 7"})
    |> render_submit()

    assert_redirect(lv, ~p"/teams/#{team}/me/details")

    assert_received {:patch, _path, body}
    assert body["deprecatedAddress"] == "2 Oak Ave"
    assert body["customFieldValues"] == [%{"id" => 630, "value" => "SF 7"}]

    [row] = Repo.all(ChangeSetRow)

    assert row.new_value == %{
             "address" => "2 Oak Ave",
             "custom_values" => %{"630" => "SF 7"}
           }

    assert ChangeHistory.describe_row(row, :member) ==
             "Contact details changed in SAR Duty. Fields changed in SAR Duty"

    member = Repo.reload!(member)
    assert member.custom_values["630"] == "SF 7"
    assert member.custom_values["856"] == "Irish"

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")
    assert has_element?(lv, "#custom-field-630[value='SF 7']")
  end

  test "a field the member only sees, or never sees, is never sent", %{
    conn: conn,
    team: team,
    member: member
  } do
    member = member_fields(team, member)
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    lv
    |> form("#details-form")
    |> render_submit(%{"fields" => %{"855" => "1990", "856" => "Scots", "1361" => ["6"]}})

    assert_redirect(lv, ~p"/teams/#{team}/me/details")
    refute_received {:patch, _path, _body}
    assert Repo.all(ChangeSet) == []
    assert Repo.reload!(member).custom_values["855"] == "1988"
  end

  test "another member's values never show", %{conn: conn, team: team, member: member} do
    member_fields(team, member)

    team
    |> member_fixture(%{custom_values: %{"630" => "SF 99", "855" => "1950"}})
    |> Repo.preload(:team)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    refute render(lv) =~ "SF 99"
    refute render(lv) =~ "1950"
  end

  test "a key that cannot fill in fields shows them read only", %{
    conn: conn,
    team: team,
    member: member
  } do
    member_fields(team, member)

    team
    |> Ecto.Changeset.change(d4h_permissions: %{"Member" => %{"UPDATE" => true}})
    |> Repo.update!()

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    refute has_element?(lv, "#custom-field-630")
    assert has_element?(lv, "#own-fields-630", "SF 12")
    assert has_element?(lv, "#own-fields-855", "1988")
  end
end
