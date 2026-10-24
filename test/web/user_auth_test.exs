# credo:disable-for-this-file Credo.Check.Readability.OnePipePerLine

defmodule Web.UserAuthTest do
  use Web.ConnCase

  import App.AccountsFixtures

  alias App.Accounts
  alias Phoenix.LiveView
  alias Web.UserAuth

  @remember_me_cookie "_sarduty_remember_me"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, Web.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{user: user_fixture(), conn: conn}
  end

  describe "log_in_user/3" do
    test "stores the user token in the session", %{conn: conn, user: user} do
      conn = UserAuth.log_in_user(conn, user)
      assert token = get_session(conn, :user_token)
      assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_user_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{conn: conn, user: user} do
      conn = conn |> put_session(:to_be_removed, "value") |> UserAuth.log_in_user(user)
      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, user: user} do
      conn = conn |> put_session(:user_return_to, "/hello") |> UserAuth.log_in_user(user)
      assert redirected_to(conn) == "/hello"
    end

    test "writes no remember-me cookie by default", %{conn: conn, user: user} do
      conn = conn |> fetch_cookies() |> UserAuth.log_in_user(user)
      refute conn.resp_cookies[@remember_me_cookie]
    end

    test "with remember: true, writes a 60-day remember-me cookie", %{conn: conn, user: user} do
      conn = conn |> fetch_cookies() |> UserAuth.log_in_user(user, remember: true)
      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :user_token)
      assert max_age == 5_184_000
    end
  end

  describe "logout_user/1" do
    test "erases session and cookies", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> put_req_cookie(@remember_me_cookie, user_token)
        |> fetch_cookies()
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute Accounts.get_user_by_session_token(user_token)
    end

    test "broadcasts to the given live_socket_id", %{conn: conn} do
      live_socket_id = "users_sessions:abcdef-token"
      Web.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> UserAuth.log_out_user()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
    end

    test "works even if user is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> UserAuth.log_out_user()
      refute get_session(conn, :user_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "assign_current_user/2" do
    test "authenticates user from session", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      conn = conn |> put_session(:user_token, user_token) |> UserAuth.assign_current_user([])
      assert conn.assigns.current_user.id == user.id
    end

    test "authenticates user from cookies", %{conn: conn, user: user} do
      logged_in_conn =
        conn |> fetch_cookies() |> UserAuth.log_in_user(user, remember: true)

      user_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> UserAuth.assign_current_user([])

      assert conn.assigns.current_user.id == user.id
      assert get_session(conn, :user_token) == user_token

      assert get_session(conn, :live_socket_id) ==
               "users_sessions:#{Base.url_encode64(user_token)}"
    end

    test "does not authenticate if data is missing", %{conn: conn, user: user} do
      _ = Accounts.generate_user_session_token(user)
      conn = UserAuth.assign_current_user(conn, [])
      refute get_session(conn, :user_token)
      refute conn.assigns.current_user
    end
  end

  describe "on_mount: mount_current_user" do
    test "assigns current_user based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == user.id
    end

    test "assigns nil to current_user assign if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
    end

    test "assigns nil to current_user assign if there isn't a user_token", %{conn: conn} do
      session = conn |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
    end
  end

  describe "on_mount: ensure_authenticated" do
    test "authenticates current_user based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:ensure_authenticated, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == user.id
    end

    test "redirects to login page if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: Web.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:ensure_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_user == nil
    end

    test "redirects to login page if there isn't a user_token", %{conn: conn} do
      session = conn |> get_session()

      socket = %LiveView.Socket{
        endpoint: Web.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:ensure_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_user == nil
    end
  end

  describe "last seen" do
    setup do
      App.DataFixtures.user_with_team_fixture()
    end

    test "opening a team LiveView records the visit", %{user: user, team: team} do
      socket = %LiveView.Socket{assigns: %{__changed__: %{}, current_user: user}}
      params = %{"subdomain" => team.subdomain}

      {:cont, _socket} =
        UserAuth.on_mount(:ensure_team_access, params, %{}, socket)

      assert Accounts.get_user!(user.id).last_seen_at
    end

    test "opening a team remembers it for the next login", %{user: user, team: team} do
      socket = %LiveView.Socket{assigns: %{__changed__: %{}, current_user: user}}
      params = %{"subdomain" => team.subdomain}
      {:cont, _socket} = UserAuth.on_mount(:ensure_team_access, params, %{}, socket)

      assert Accounts.get_user!(user.id).last_team_id == team.id
    end

    test "opening a team controller page records the visit", %{conn: conn, user: user, team: team} do
      conn
      |> assign(:current_user, user)
      |> Map.put(:path_params, %{"subdomain" => team.subdomain})
      |> UserAuth.require_authorized_team_subdomain([])

      assert Accounts.get_user!(user.id).last_seen_at
    end

    test "an admin's visit is not recorded", %{conn: conn, team: team} do
      admin = user_fixture(%{is_admin: true})

      conn
      |> assign(:current_user, admin)
      |> Map.put(:path_params, %{"subdomain" => team.subdomain})
      |> UserAuth.require_authorized_team_subdomain([])

      refute Accounts.get_user!(admin.id).last_seen_at
    end
  end

  describe "on_mount: ensure_team_access" do
    defp mount_team(user, team, view) do
      socket = %LiveView.Socket{view: view, assigns: %{__changed__: %{}, current_user: user}}
      UserAuth.on_mount(:ensure_team_access, %{"subdomain" => team.subdomain}, %{}, socket)
    end

    test "a member opens a member page, as a member and not a team admin" do
      %{team: team, user: user, member: member} = App.DataFixtures.member_with_login_fixture()

      {:cont, socket} = mount_team(user, team, Web.MeLive)

      assert socket.assigns.current_team.id == team.id
      assert socket.assigns.current_member.id == member.id
      refute socket.assigns.team_admin?
      assert socket.assigns.proposed_change_count == 0
      refute Accounts.get_user!(user.id).last_seen_at
    end

    test "a member gets a 404 from a page for team admins" do
      %{team: team, user: user} = App.DataFixtures.member_with_login_fixture()

      assert_raise Web.Status.NotFound, fn -> mount_team(user, team, Web.GroupCollectionLive) end
    end

    test "a team admin who is a member is both, on the URL's team" do
      %{team: team, user: user, member: member} =
        App.DataFixtures.member_with_login_fixture(%{d4h_permission: 0})

      other = App.DataFixtures.team_fixture()
      App.DataFixtures.manager_fixture(other, %{email: user.email})
      user = %{user | last_team_id: other.id}

      {:cont, socket} = mount_team(user, team, Web.MeLive)
      assert socket.assigns.current_team.id == team.id
      assert socket.assigns.current_member.id == member.id
      assert socket.assigns.team_admin?

      {:cont, socket} = mount_team(user, team, Web.TeamDashboardLive)
      assert socket.assigns.current_member.id == member.id
    end

    test "a SAR Duty admin opens a team's pages but not its member pages" do
      admin = user_fixture(%{is_admin: true})
      team = App.DataFixtures.team_fixture()

      {:cont, socket} = mount_team(admin, team, Web.TeamDashboardLive)
      assert socket.assigns.team_admin?
      assert socket.assigns.current_member == nil

      assert_raise Web.Status.NotFound, fn -> mount_team(admin, team, Web.MeLive) end
    end

    test "someone who is neither gets a 404", %{user: user} do
      team = App.DataFixtures.member_logins_team_fixture()

      assert_raise Web.Status.NotFound, fn -> mount_team(user, team, Web.MeLive) end
      assert_raise Web.Status.NotFound, fn -> mount_team(user, team, Web.TeamDashboardLive) end
    end

    test "a page is for team admins unless it says otherwise" do
      assert UserAuth.page_access(Web.GroupCollectionLive) == :admin
      assert UserAuth.page_access(Web.TeamDashboardLive) == :team
      assert UserAuth.page_access(Web.MeLive) == :member
      assert UserAuth.page_access(nil) == :admin
    end

    # Opening a page to members doesn't open its actions (#440).
    test "a page lists the events that only change what it shows" do
      assert UserAuth.view_events(Web.TeamDashboardLive) == []
      assert UserAuth.view_events(Web.MemberCollectionLive) == ["change"]
      assert UserAuth.view_events(Web.MemberQualificationsLive) == []
      assert UserAuth.view_events(Web.MeChoreFormLive) == ["validate"]
    end
  end

  describe "signed_in_path/1" do
    test "lands on the only team, or the last one opened among several", %{user: user} do
      north = App.DataFixtures.team_fixture(%{name: "North SAR"})
      south = App.DataFixtures.team_fixture(%{name: "South SAR"})
      App.DataFixtures.manager_fixture(north, %{email: user.email})

      assert UserAuth.signed_in_path(user) == ~p"/teams/#{north}"

      App.DataFixtures.manager_fixture(south, %{email: user.email})
      assert UserAuth.signed_in_path(user) == ~p"/teams/#{north}"
      assert UserAuth.signed_in_path(%{user | last_team_id: south.id}) == ~p"/teams/#{south}"
    end

    test "a member who manages no team lands on their team's Dashboard" do
      %{team: team, user: user} = App.DataFixtures.member_with_login_fixture()
      assert UserAuth.signed_in_path(user) == ~p"/teams/#{team}"
    end

    test "an admin with no team lands on /admin; anyone else on the home page" do
      admin = user_fixture(%{is_admin: true})
      assert UserAuth.signed_in_path(admin) == ~p"/admin"
      assert UserAuth.signed_in_path(user_fixture()) == ~p"/"
    end
  end

  describe "team access" do
    setup do
      App.DataFixtures.user_with_team_fixture()
    end

    defp open(conn, user, team) do
      conn
      |> assign(:current_user, user)
      |> Map.put(:path_params, %{"subdomain" => team.subdomain})
      |> UserAuth.require_authorized_team_subdomain([])
    end

    test "a manager opens their team", %{conn: conn, user: user, team: team} do
      assert open(conn, user, team).assigns.current_team.id == team.id
    end

    test "a manager can't open another team", %{conn: conn, user: user} do
      other = App.DataFixtures.team_fixture()
      assert_raise Web.Status.NotFound, fn -> open(conn, user, other) end
    end

    test "losing Owner or Editor in D4H loses the team", %{conn: conn, user: user, team: team} do
      App.Repo.update_all(App.Model.Member, set: [d4h_permission: 2])
      assert_raise Web.Status.NotFound, fn -> open(conn, user, team) end
    end

    test "an admin opens any team", %{conn: conn} do
      admin = user_fixture(%{is_admin: true})
      other = App.DataFixtures.team_fixture()
      assert open(conn, admin, other).assigns.current_team.id == other.id
    end

    test "pages outside a team use the first team the user manages", %{conn: conn, user: user} do
      token = Accounts.generate_user_session_token(user)
      conn = conn |> put_session(:user_token, token) |> UserAuth.assign_current_user([])
      assert conn.assigns.current_team
    end
  end

  describe "require_authenticated_user/2" do
    test "redirects if user is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> UserAuth.require_authenticated_user([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/login"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Log in to see this page."
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      refute get_session(halted_conn, :user_return_to)
    end

    test "does not redirect if user is authenticated", %{conn: conn, user: user} do
      conn = conn |> assign(:current_user, user) |> UserAuth.require_authenticated_user([])
      refute conn.halted
      refute conn.status
    end
  end
end
