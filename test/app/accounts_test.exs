defmodule App.AccountsTest do
  use App.DataCase

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Accounts
  alias App.Accounts.User
  alias App.Accounts.UserToken
  alias App.Model.Team
  alias App.Model.TeamLoginGrant

  @now ~U[2026-10-04 12:00:00Z]

  describe "may_log_in?/2" do
    test "a current Owner or Editor on a team may, in any letter case" do
      team = team_fixture()
      manager_fixture(team, %{email: "owner@example.com"})
      manager_fixture(team, %{email: "editor@example.com", d4h_permission: 1})

      assert Accounts.may_log_in?("Owner@Example.com", @now)
      assert Accounts.may_log_in?("editor@example.com", @now)
    end

    test "members, retired managers, and managers who left may not" do
      team = team_fixture()
      manager_fixture(team, %{email: "member@example.com", d4h_permission: 2})
      manager_fixture(team, %{email: "retired@example.com", d4h_status: "RETIRED"})
      manager_fixture(team, %{email: "left@example.com", left_at: ~U[2026-01-01 00:00:00Z]})

      refute Accounts.may_log_in?("member@example.com", @now)
      refute Accounts.may_log_in?("retired@example.com", @now)
      refute Accounts.may_log_in?("left@example.com", @now)
      refute Accounts.may_log_in?("nobody@example.com", @now)
    end

    test "a SAR Duty team key account doesn't make its email a manager" do
      team = team_fixture(%{d4h_access_key_member_id: 900, d4h_access_key_owner: "SAR Duty"})
      manager_fixture(team, %{email: "sarduty@example.com", d4h_member_id: 900})

      refute Accounts.may_log_in?("sarduty@example.com", @now)
    end

    test "a manager whose own key is the team key still may" do
      team = team_fixture(%{d4h_access_key_member_id: 901, d4h_access_key_owner: "Kim Lee"})
      manager_fixture(team, %{email: "kim@example.com", d4h_member_id: 901})

      assert Accounts.may_log_in?("kim@example.com", @now)
    end

    test "an email an admin let into a team may, and reaches only that team" do
      team = team_fixture()
      TeamLoginGrant.grant!(team.subdomain, " Shared@Example.com ", "role address")

      assert Accounts.may_log_in?("shared@example.com", @now)
      assert [%{id: id}] = Team.get_managed_by("SHARED@example.com", @now)
      assert id == team.id

      TeamLoginGrant.revoke!(team.subdomain, "shared@example.com")
      refute Accounts.may_log_in?("shared@example.com", @now)
    end

    test "an admin may without managing a team" do
      user_fixture(%{email: "admin@example.com", is_admin: true})

      assert Accounts.may_log_in?("admin@example.com", @now)
    end
  end

  describe "Team.get_managed_by/2" do
    test "lists every team the email manages, by name" do
      north = team_fixture(%{name: "North SAR"})
      south = team_fixture(%{name: "South SAR"})
      other = team_fixture(%{name: "Other SAR"})
      manager_fixture(south, %{email: "sam@example.com"})
      manager_fixture(north, %{email: "sam@example.com", d4h_permission: 1})
      manager_fixture(other, %{email: "sam@example.com", d4h_permission: 2})

      managed = "sam@example.com" |> Team.get_managed_by(@now) |> Enum.map(& &1.id)
      assert managed == [north.id, south.id]
    end
  end

  describe "login links" do
    test "sends a link to a manager, and makes their user" do
      manager_fixture(team_fixture(), %{email: "pat@example.com"})

      token = extract_user_token(&deliver(" Pat@Example.com ", &1))

      assert %User{email: "pat@example.com"} = Accounts.get_user_by_login_token(token)
    end

    test "sends nothing, and makes no user, for an email that may not log in" do
      assert Accounts.deliver_login_link("stranger@example.com", &"url/#{&1}") == :ok
      refute Accounts.get_user_by_email("stranger@example.com")
      assert Repo.aggregate(UserToken, :count) == 0
    end

    test "a link works once, and logs in its user" do
      %{user: user} = user_with_team_fixture()
      token = extract_user_token(&deliver(user.email, &1))

      assert {:ok, %User{id: id, confirmed_at: confirmed_at}} = Accounts.log_in_with_token(token)
      assert id == user.id
      assert confirmed_at
      assert Accounts.log_in_with_token(token) == :error
    end

    test "a link expires after 15 minutes" do
      %{user: user} = user_with_team_fixture()
      token = extract_user_token(&deliver(user.email, &1))
      sixteen_minutes_ago = DateTime.add(DateTime.utc_now(), -16, :minute)
      Repo.update_all(UserToken, set: [inserted_at: sixteen_minutes_ago])

      refute Accounts.get_user_by_login_token(token)
      assert Accounts.log_in_with_token(token) == :error
    end

    test "a second request within a minute sends nothing more" do
      manager_fixture(team_fixture(), %{email: "twice@example.com"})

      :ok = Accounts.deliver_login_link("twice@example.com", &"url/#{&1}")
      :ok = Accounts.deliver_login_link("twice@example.com", &"url/#{&1}")

      assert_received {:email, _}
      refute_received {:email, _}
      assert Repo.aggregate(UserToken, :count) == 1
    end

    test "a link token is 26 lowercase letters and digits" do
      {token, _user_token} = UserToken.build_login_token(user_fixture())
      assert token =~ ~r/\A[a-z2-7]{26}\z/
    end

    test "the email has the link in its text and a Log in button" do
      manager_fixture(team_fixture(), %{email: "html@example.com"})

      :ok = Accounts.deliver_login_link("html@example.com", &"https://sarduty.test/login/#{&1}")

      assert_received {:email, email}
      [url] = Regex.run(~r{https://sarduty.test/login/[a-z2-7]+}, email.text_body)
      assert email.html_body =~ ~s(href="#{url}")
      assert email.html_body =~ ">Log in</a>"
    end

    test "a malformed token is no user" do
      refute Accounts.get_user_by_login_token("not a token")
    end
  end

  describe "sessions" do
    test "a session token finds its user until deleted" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert Accounts.get_user_by_session_token(token).id == user.id
      Accounts.delete_user_session_token(token)
      refute Accounts.get_user_by_session_token(token)
    end
  end

  # Delivers through the test mailer and hands the sent email to extract_user_token/1.
  defp deliver(email, url_fun) do
    :ok = Accounts.deliver_login_link(email, url_fun)
    assert_received {:email, sent}
    {:ok, sent}
  end
end
