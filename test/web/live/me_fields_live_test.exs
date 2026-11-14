defmodule Web.MeFieldsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Web.OwnDetails

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Repo
  alias App.ViewData.ChangeHistory

  setup :member_logged_in

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
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/fields")

    assert has_element?(lv, "#fields-form #custom-field-630[value='SF 12']")
    refute has_element?(lv, "#own-fields-630")
    assert has_element?(lv, "#own-fields-855", "1988")
    refute has_element?(lv, "#custom-field-855")
    refute has_element?(lv, "#own-fields-1361")
    refute has_element?(lv, "#custom-field-1361")
    refute has_element?(lv, "#own-fields-856")
    refute render(lv) =~ "Irish"
  end

  test "Save fields sends a changed field straight to D4H, and history names no value",
       %{conn: conn, team: team, member: member} do
    member = member_fields(team, member)
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/fields")

    lv
    |> form("#fields-form", fields: %{"630" => "SF 7"})
    |> render_submit()

    assert_redirect(lv, ~p"/teams/#{team}/me")

    assert_received {:patch, _path, body}
    refute Map.has_key?(body, "deprecatedAddress")
    assert body["customFieldValues"] == [%{"id" => 630, "value" => "SF 7"}]

    [row] = Repo.all(ChangeSetRow)

    assert row.new_value == %{"custom_values" => %{"630" => "SF 7"}}

    assert ChangeHistory.describe_row(row, :member) ==
             "Fields changed in SAR Duty"

    member = Repo.reload!(member)
    assert member.custom_values["630"] == "SF 7"
    assert member.custom_values["856"] == "Irish"

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/fields")
    assert has_element?(lv, "#custom-field-630[value='SF 7']")
  end

  test "a field the member only sees, or never sees, is never sent", %{
    conn: conn,
    team: team,
    member: member
  } do
    member = member_fields(team, member)
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/fields")

    lv
    |> form("#fields-form")
    |> render_submit(%{"fields" => %{"855" => "1990", "856" => "Scots", "1361" => ["6"]}})

    assert_redirect(lv, ~p"/teams/#{team}/me")
    refute_received {:patch, _path, _body}
    assert Repo.all(ChangeSet) == []
    assert Repo.reload!(member).custom_values["855"] == "1988"
  end

  test "another member's values never show", %{conn: conn, team: team, member: member} do
    member_fields(team, member)

    team
    |> member_fixture(%{custom_values: %{"630" => "SF 99", "855" => "1950"}})
    |> Repo.preload(:team)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/fields")

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

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/fields")

    refute has_element?(lv, "#fields-form")
    assert has_element?(lv, "#own-fields-630", "SF 12")
    assert has_element?(lv, "#own-fields-855", "1988")
  end

  test "Your membership links here only when the team has fields a member sees",
       %{conn: conn, team: team, member: member} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
    refute has_element?(lv, "#change-fields")

    member_fields(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
    assert has_element?(lv, ~s{#change-fields[href="/teams/#{team.subdomain}/me/fields"]})
  end
end
