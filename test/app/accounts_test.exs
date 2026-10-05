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

    test "an admin who is a current member somewhere may, without managing a team" do
      team = team_fixture()
      manager_fixture(team, %{email: "admin@example.com", d4h_permission: 2})
      user_fixture(%{email: "admin@example.com", is_admin: true})

      assert Accounts.may_log_in?("admin@example.com", @now)
    end

    test "an admin D4H doesn't list, or lists as retired or left, may not" do
      team = team_fixture()
      manager_fixture(team, %{email: "retired@example.com", d4h_status: "RETIRED"})
      manager_fixture(team, %{email: "left@example.com", left_at: ~U[2026-01-01 00:00:00Z]})

      for email <- ["nobody@example.com", "retired@example.com", "left@example.com"] do
        user_fixture(%{email: email, is_admin: true})
        refute Accounts.may_log_in?(email, @now)
      end
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

  describe "login codes" do
    test "emails a manager a six-digit code, and makes their user" do
      manager_fixture(team_fixture(), %{email: "pat@example.com"})

      code = deliver(" Pat@Example.com ")

      assert code =~ ~r/\A\d{6}\z/

      assert {:ok, %User{email: "pat@example.com"}} =
               Accounts.log_in_with_code("pat@example.com", code)
    end

    test "sends nothing, and makes no user, for an email that may not log in" do
      assert Accounts.deliver_login_code("stranger@example.com") == :ok
      refute Accounts.get_user_by_email("stranger@example.com")
      assert Repo.aggregate(UserToken, :count) == 0
    end

    test "a code works once, with spaces and in any email case" do
      %{user: user} = user_with_team_fixture()
      code = deliver(user.email)
      spaced = String.slice(code, 0, 3) <> " " <> String.slice(code, 3, 3)

      upcased = String.upcase(user.email)

      assert {:ok, %User{id: id}} = Accounts.log_in_with_code(upcased, spaced)
      assert id == user.id
      assert Accounts.log_in_with_code(user.email, code) == :error
    end

    test "a code expires after 15 minutes" do
      %{user: user} = user_with_team_fixture()
      code = deliver(user.email)
      sixteen_minutes_ago = DateTime.add(DateTime.utc_now(), -16, :minute)
      Repo.update_all(UserToken, set: [inserted_at: sixteen_minutes_ago])

      assert Accounts.log_in_with_code(user.email, code) == :error
    end

    test "a code dies after 5 wrong tries" do
      %{user: user} = user_with_team_fixture()
      code = deliver(user.email)
      wrong = if code == "000000", do: "111111", else: "000000"

      for _ <- 1..5, do: assert(Accounts.log_in_with_code(user.email, wrong) == :error)

      assert Accounts.log_in_with_code(user.email, code) == :error
    end

    test "a code is no good for another email" do
      %{user: user} = user_with_team_fixture()
      %{user: other} = user_with_team_fixture()
      code = deliver(user.email)

      assert Accounts.log_in_with_code(other.email, code) == :error
      assert Accounts.log_in_with_code("nobody@example.com", code) == :error
    end

    test "a second request within a minute sends nothing more" do
      manager_fixture(team_fixture(), %{email: "twice@example.com"})

      :ok = Accounts.deliver_login_code("twice@example.com")
      :ok = Accounts.deliver_login_code("twice@example.com")

      assert_received {:email, _}
      refute_received {:email, _}
      assert Repo.aggregate(UserToken, :count) == 1
    end

    test "a later request replaces the code" do
      %{user: user} = user_with_team_fixture()
      first = deliver(user.email)

      Repo.update_all(UserToken,
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -2, :minute)]
      )

      second = deliver(user.email)

      assert Repo.aggregate(UserToken, :count) == 1
      if first != second, do: assert(Accounts.log_in_with_code(user.email, first) == :error)
      assert {:ok, _} = Accounts.log_in_with_code(user.email, second)
    end

    test "the database keeps only the code's hash" do
      %{user: user} = user_with_team_fixture()
      code = deliver(user.email)

      refute Repo.one!(UserToken).token == code
    end

    test "the code is in the subject, the text, and the HTML" do
      manager_fixture(team_fixture(), %{email: "html@example.com"})

      :ok = Accounts.deliver_login_code("html@example.com")

      assert_received {:email, email}
      [code] = Regex.run(~r/\d{6}/, email.subject)
      assert email.text_body =~ code
      assert email.html_body =~ code
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

  # Sends a code through the test mailer and returns it.
  defp deliver(email) do
    :ok = Accounts.deliver_login_code(email)
    assert_received {:email, sent}
    [code] = Regex.run(~r/\d{6}/, sent.subject)
    code
  end
end
