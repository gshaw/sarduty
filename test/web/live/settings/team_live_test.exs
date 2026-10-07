defmodule Web.Settings.TeamLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Event
  alias App.Model.Team
  alias App.Repo

  @secret "SECRET-TEAM-PAT-123"

  test "renders team settings when team exists", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/settings")

    assert html =~ "Team settings"
  end

  test "never puts the saved team key in the page", %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{
        team: %{d4h_access_key: @secret, d4h_access_key_saved_at: ~U[2026-08-01 18:00:00Z]}
      })

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/settings")

    refute html =~ @secret
    refute render(lv) =~ @secret
    assert has_element?(lv, "#form_new_d4h_access_key")
    refute has_element?(lv, "#form_new_d4h_access_key[value]")
    assert has_element?(lv, "#team-key-status", "Key saved August 1, 2026")
  end

  test "says when no team key is saved", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/settings")

    assert has_element?(lv, "#team-key-status", "SAR Duty cannot reach D4H")
  end

  test "saving with a blank key field keeps the saved key", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: @secret}})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/settings")

    html =
      lv
      |> form("form", form: %{name: "Renamed SAR", new_d4h_access_key: ""})
      |> render_submit()

    assert html =~ "Team settings saved."
    refute html =~ @secret

    team = Team.get!(team.id)
    assert team.name == "Renamed SAR"
    assert team.d4h_access_key == @secret
  end

  test "a new key is saved and recorded as changed, by whom", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: @secret}})

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      owner = %{"resourceType" => "Team", "id" => team.d4h_team_id, "title" => team.name}

      Req.Test.json(conn, %{
        "members" => [
          %{"resourceType" => "Member", "id" => 900, "name" => "SAR Duty", "owner" => owner}
        ]
      })
    end)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

    assert lv
           |> form("form", form: %{new_d4h_access_key: "new-key"})
           |> render_submit() =~ "Team settings saved."

    assert Team.get!(team.id).d4h_access_key == "new-key"

    assert %Event{team_id: team_id, user_id: user_id, data: %{"sar_duty_account" => true}} =
             Event.get_last(:team_key_changed)

    assert {team_id, user_id} == {team.id, user.id}
  end

  test "names the key's D4H member and asks for a SAR Duty account", %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{
        team: %{d4h_access_key: @secret, d4h_access_key_owner: "Sam Rivers"}
      })

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

    assert has_element?(lv, "#team-key-owner", "Sam Rivers")
    assert has_element?(lv, "#team-key-advice", "SAR Duty")
  end

  test "drops the advice once the key is a SAR Duty account's", %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{
        team: %{d4h_access_key: @secret, d4h_access_key_owner: "SAR Duty"}
      })

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

    assert has_element?(lv, "#team-key-owner", "SAR Duty")
    refute has_element?(lv, "#team-key-advice")
  end

  test "changes the team in the URL, not the one last opened", %{conn: conn} do
    %{user: user, team: first} = user_with_team_fixture()
    second = team_fixture(%{name: "Second SAR"})
    manager_fixture(second, %{email: user.email})
    App.Repo.update_all(App.Accounts.User, set: [last_team_id: first.id])

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{second}/settings")

    lv |> form("form", form: %{name: "Renamed Second"}) |> render_submit()

    assert Team.get!(second.id).name == "Renamed Second"
    assert Team.get!(first.id).name == first.name
  end

  test "404s for a team the user doesn't manage", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    other = team_fixture()

    assert_error_sent 404, fn ->
      conn |> log_in_user(user) |> get(~p"/teams/#{other}/settings")
    end
  end

  describe "the signer's signature" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      %{conn: log_in_user(conn, user), team: team}
    end

    defp upload(lv, bytes, name \\ "signature.png") do
      lv
      |> file_input("#team_settings_form", :signature, [
        %{name: name, content: bytes, type: "image/png"}
      ])
      |> render_upload(name)

      lv |> form("#team_settings_form") |> render_submit()
    end

    test "uploads as a PNG, shows a preview, and removes", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings")
      refute has_element?(lv, "#signature-preview")

      upload(lv, png_fixture(1800, 400))

      assert has_element?(lv, "#signature-preview")
      signature = Repo.get!(Team, team.id).signature
      assert {:ok, image} = Image.from_binary(signature)
      # Scaled down to fit 900 pixels.
      assert Image.width(image) == 900

      lv |> element("#remove-signature") |> render_click()

      refute has_element?(lv, "#signature-preview")
      assert Repo.get!(Team, team.id).signature == nil
    end

    test "a file that is not an image is not saved", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings")

      upload(lv, "not an image")

      assert has_element?(lv, "#signature-error", "Use a PNG or JPEG image of the signature.")
      assert Repo.get!(Team, team.id).signature == nil
    end
  end
end
