defmodule Web.Settings.AccessKeyLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.D4HAccess
  alias App.Model.Event
  alias App.Model.Team

  @secret "SECRET-TEAM-PAT-123"
  @checked ~U[2026-10-29 17:10:00.000000Z]

  # Every right SAR Duty uses, true, like an Owner's key.
  defp all_rights do
    for feature <- D4HAccess.features(), {resource, action} <- feature.needs, reduce: %{} do
      acc -> put_in(acc, [Access.key(resource, %{}), action], true)
    end
  end

  defp whoami(team, permissions) do
    owner = %{"resourceType" => "Team", "id" => team.d4h_team_id, "title" => team.name}

    %{
      "members" => [
        %{"resourceType" => "Member", "id" => 900, "name" => "SAR Duty", "owner" => owner}
      ],
      "context" => %{"permissions" => permissions}
    }
  end

  test "never puts the saved team key in the page", %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{
        team: %{d4h_access_key: @secret, d4h_access_key_saved_at: ~U[2026-08-01 18:00:00Z]}
      })

    {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/access-key")

    refute html =~ @secret
    refute render(lv) =~ @secret
    assert has_element?(lv, "#form_new_d4h_access_key")
    refute has_element?(lv, "#form_new_d4h_access_key[value]")
    assert has_element?(lv, "#team-key-saved", "August 1, 2026")
  end

  test "says when no team key is saved", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/access-key")

    assert has_element?(lv, "#team-key-missing", "SAR Duty cannot reach D4H")
    refute has_element?(lv, "#key-rights")
  end

  test "a blank key asks for one and keeps the saved key", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: @secret}})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/access-key")

    html =
      lv |> form("#team_key_form", form: %{new_d4h_access_key: ""}) |> render_submit()

    assert html =~ "Paste the new key."
    assert Team.get!(team.id).d4h_access_key == @secret
  end

  test "a new key is saved with what D4H lets it do, and recorded as changed, by whom",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: @secret}})
    Req.Test.stub(App.Adapter.D4H, &Req.Test.json(&1, whoami(team, all_rights())))

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/access-key")

    assert lv
           |> form("#team_key_form", form: %{new_d4h_access_key: "new-key"})
           |> render_submit() =~ "Key saved."

    team = Team.get!(team.id)
    assert team.d4h_access_key == "new-key"
    assert team.d4h_permissions == all_rights()
    assert has_element?(lv, "#key-can-all")

    assert %Event{team_id: team_id, user_id: user_id, data: %{"sar_duty_account" => true}} =
             Event.get_last(:team_key_changed)

    assert {team_id, user_id} == {team.id, user.id}
  end

  test "an Owner's key can do everything", %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{
        team: %{
          d4h_access_key: @secret,
          d4h_access_key_owner: "SAR Duty",
          d4h_access_key_member_id: 900,
          d4h_permissions: all_rights(),
          d4h_permissions_checked_at: @checked
        }
      })

    member_fixture(team, %{d4h_member_id: 900, name: "SAR Duty", d4h_permission: 0})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/access-key")

    assert has_element?(lv, "#team-key-owner", "SAR Duty, an Owner in D4H")
    assert has_element?(lv, "#key-can-all", "The key can do everything SAR Duty does.")
    assert has_element?(lv, "#key-checked", "Checked")
    refute has_element?(lv, "#key-refused")
    refute has_element?(lv, "#team-key-advice")
  end

  test "an Editor's key D4H limits names what it refuses and the fix", %{conn: conn} do
    rights = put_in(all_rights(), ["MemberGroup", "UPDATE"], false)

    %{user: user, team: team} =
      user_with_team_fixture(%{
        team: %{
          d4h_access_key: @secret,
          d4h_access_key_owner: "SAR Duty",
          d4h_access_key_member_id: 900,
          d4h_permissions: rights,
          d4h_permissions_checked_at: @checked
        }
      })

    member_fixture(team, %{d4h_member_id: 900, name: "SAR Duty", d4h_permission: 1})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/access-key")

    assert has_element?(
             lv,
             "#key-refused",
             "SAR Duty is an Editor in D4H, and D4H refuses an Editor's key to change groups."
           )

    assert has_element?(lv, "#key-refused", "make SAR Duty an Owner")
    assert has_element?(lv, "#key-refused-groups", "Change groups")
    assert has_element?(lv, "#key-can-most")
    refute has_element?(lv, "#key-refused-attendance")
  end

  test "Check again reads the key's rights from D4H", %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{
        team: %{d4h_access_key: @secret, d4h_access_key_owner: "SAR Duty"}
      })

    rights = put_in(all_rights(), ["Whiteboard", "CREATE"], false)
    Req.Test.stub(App.Adapter.D4H, &Req.Test.json(&1, whoami(team, rights)))

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/access-key")
    assert has_element?(lv, "#key-unchecked")

    assert lv |> element("#check-key") |> render_click() =~ "Key checked."
    assert has_element?(lv, "#key-refused-whiteboard", "Whiteboard")
    assert Team.get!(team.id).d4h_permissions_checked_at
  end

  test "Check again says when D4H refuses the key", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: @secret}})
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 401, ""))

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/access-key")

    assert lv |> element("#check-key") |> render_click() =~ "D4H refused the key."
  end

  test "names the key's D4H member and asks for a SAR Duty account", %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{
        team: %{d4h_access_key: @secret, d4h_access_key_owner: "Sam Rivers"}
      })

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/access-key")

    assert has_element?(lv, "#team-key-owner", "Sam Rivers")
    assert has_element?(lv, "#team-key-advice", "SAR Duty")
  end
end
