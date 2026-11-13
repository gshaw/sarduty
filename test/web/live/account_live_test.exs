defmodule Web.AccountLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

  test "is Account settings: the email, and the account menu", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    other = team_fixture(%{name: "Other SAR"})
    manager_fixture(other, %{email: user.email})

    {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/account")

    assert has_element?(lv, "h1", "Account settings")
    assert has_element?(lv, "#account-email", user.email)
    assert has_element?(lv, "#nav-area", "Account settings")
    assert has_element?(lv, ~s{#account-menu #nav-account-settings[href="/account"]})
    assert has_element?(lv, ~s{#switch-team-#{team.subdomain}[href="/teams/#{team.subdomain}"]})
    refute has_element?(lv, "#side-nav")
    refute html =~ "Change password"
  end

  test "saves the maps app place links open", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

    assert has_element?(lv, "#maps-app-google[checked]")

    lv |> form("#maps-app-form", %{maps_app: "apple"}) |> render_change()

    assert has_element?(lv, "#maps-app-apple[checked]")
    assert Repo.reload!(user).maps_app == "apple"

    lv |> element("#maps-app-form") |> render_change(%{maps_app: "bing"})
    assert Repo.reload!(user).maps_app == "apple"
  end

  test "a user who manages no team sees no team settings", %{conn: conn} do
    {:ok, _lv, html} = conn |> log_in_user(user_fixture()) |> live(~p"/account")

    refute html =~ "Team settings"
  end

  test "an invitation reminders switch for the team the user logs in to (#444)",
       %{conn: conn} do
    %{member: member, user: user} = member_with_login_fixture()
    id = "#invitation-reminders-#{member.team.subdomain}"
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

    assert has_element?(lv, "#emails h2", "Emails")

    assert has_element?(
             lv,
             "label[for=#{String.trim_leading(id, "#")}]",
             ~r/^\s*Invitation reminders\s*$/
           )

    assert has_element?(lv, "#{id}[checked]")

    lv |> element(id) |> render_click()
    refute Repo.reload(member).invitation_reminders
    refute has_element?(lv, "#{id}[checked]")

    lv |> element(id) |> render_click()
    assert Repo.reload(member).invitation_reminders
  end

  test "names the team when the user logs in to several", %{conn: conn} do
    %{member: member, user: user} = member_with_login_fixture()
    other = member_logins_team_fixture(%{name: "Other SAR"})
    other_member = member_fixture(other, %{email: user.email})
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

    assert has_element?(lv, "#emails", "Invitation reminders from #{member.team.name}")
    assert has_element?(lv, "#emails", "Invitation reminders from Other SAR")

    lv |> element("#invitation-reminders-#{other.subdomain}") |> render_click()
    refute Repo.reload(other_member).invitation_reminders
    assert Repo.reload(member).invitation_reminders
  end

  test "taps only change the user's own members", %{conn: conn} do
    %{user: user} = member_with_login_fixture()
    %{member: someone} = member_with_login_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

    render_click(lv, "reminders", %{"id" => to_string(someone.id)})
    assert Repo.reload(someone).invitation_reminders
  end

  test "no Emails without a member login", %{conn: conn} do
    {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/account")

    refute has_element?(lv, "#emails")
  end

  test "a team admin viewing as a member cannot change their own reminders (#425)",
       %{conn: conn} do
    %{team: team, member: sam} = member_with_login_fixture()
    admin = user_fixture()
    own = manager_fixture(team, %{email: admin.email})
    conn = conn |> log_in_user(admin) |> post(~p"/teams/#{team}/members/#{sam}/view-as")
    {:ok, lv, _html} = live(conn, ~p"/account")

    assert has_element?(lv, "#emails-view-as")
    assert has_element?(lv, "#invitation-reminders-#{team.subdomain}[disabled]")

    render_click(lv, "reminders", %{"id" => to_string(own.id)})
    assert Repo.reload(own).invitation_reminders
    assert Repo.reload(sam).invitation_reminders
  end

  test "redirects if user is not logged in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/account")
  end

  describe "passkeys (#129)" do
    import App.PasskeyFixtures

    alias App.Accounts.UserPasskey
    alias App.Accounts.WebAuthn
    alias App.Model.Event

    test "every account gets the section", %{conn: conn} do
      {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/account")

      assert has_element?(lv, "#passkeys h2", "Passkeys")
      assert has_element?(lv, "#passkeys-empty", "No passkeys yet.")
      assert has_element?(lv, "#passkey-add[phx-hook=PasskeyAdd]", "Add a passkey")
    end

    test "adds a passkey the browser made, and emails about it", %{conn: conn} do
      user = user_fixture(%{email: "alex.chen@example.com"})
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

      render_hook(lv, "passkey-options", %{})
      assert_reply(lv, %{challenge: text, rp: %{id: rp_id}, excludeCredentials: []})
      {:ok, bytes} = WebAuthn.decode(text)
      challenge = %{bytes: bytes, rp_id: rp_id, origin: Web.Endpoint.url()}

      params = create_answer(authenticator(), challenge)
      html = render_hook(lv, "passkey-created", params)

      assert html =~ "Passkey added."
      assert [%UserPasskey{id: id, name: "iCloud Keychain"}] = UserPasskey.list_for(user)
      assert has_element?(lv, "#passkey-#{id}", "iCloud Keychain")
      assert has_element?(lv, "#passkey-#{id}", "Never")
      assert_received {:email, %{subject: "Passkey added to your SAR Duty account"}}
      assert %Event{data: %{"passkey" => "iCloud Keychain"}} = Event.get_last(:passkey_added)

      # The challenge is used up.
      render_hook(lv, "passkey-created", params)
      assert length(UserPasskey.list_for(user)) == 1
    end

    test "says why when the browser refused", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

      assert render_hook(lv, "passkey-failed", %{"name" => "InvalidStateError"}) =~
               "This device already has a passkey for your account."

      assert render_hook(lv, "passkey-failed", %{"name" => "SecurityError"}) =~
               "Your browser could not make a passkey."
    end

    test "removes a passkey after asking", %{conn: conn} do
      user = user_fixture()
      {passkey, _key} = passkey_fixture(user)
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

      button = "#passkey-remove-#{passkey.id}"

      assert has_element?(
               lv,
               ~s(#{button}[data-confirm="Remove iCloud Keychain? It can no longer log you in."])
             )

      html = lv |> element(button) |> render_click()

      assert html =~ "Passkey removed."
      refute has_element?(lv, "#passkey-#{passkey.id}")
      assert UserPasskey.list_for(user) == []
      assert Event.get_last(:passkey_removed)
    end

    test "the challenge the page made is the one the passkey must answer", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")
      render_hook(lv, "passkey-options", %{})

      html =
        render_hook(
          lv,
          "passkey-created",
          create_answer(authenticator(), WebAuthn.registration_challenge())
        )

      assert html =~ "SAR Duty could not add that passkey."
      assert UserPasskey.list_for(user) == []
    end
  end
end
