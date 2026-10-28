defmodule Web.InvitationRemindersLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Activity
  alias App.Model.Member
  alias App.Repo
  alias Web.ReplyLinks

  setup do
    team = team_fixture(%{name: "Coast Range SAR"})
    %{member: member_fixture(team, %{name: "Cameron Ruiz"})}
  end

  test "opening the link changes nothing; one button turns reminders off, then on",
       %{conn: conn, member: member} do
    {:ok, lv, _html} = live(conn, ReplyLinks.reminders_path(member))

    assert has_element?(lv, "h1", "Turn off invitation reminders?")
    assert has_element?(lv, ".hint", "Coast Range SAR · Cameron Ruiz")
    assert Repo.reload(member).invitation_reminders

    lv |> element("#reminders-off") |> render_click()
    assert has_element?(lv, "h1", "Invitation reminders are off")
    refute Repo.reload(member).invitation_reminders
    assert has_element?(lv, ~s{#reminders-account[href="/account"]}, "Open account settings")

    lv |> element("#reminders-on") |> render_click()
    assert Repo.reload(member).invitation_reminders
  end

  test "a reply link doesn't turn reminders off", %{conn: conn, member: member} do
    "/replies/" <> token = ReplyLinks.reply_path(member, %Activity{id: 1})
    {:ok, lv, _html} = live(conn, "/reminders/" <> token)

    assert has_element?(lv, "h1", "This link does not work")
  end

  # A mail app's one-click unsubscribe (RFC 8058) posts with no session or CSRF token.
  test "a one-click unsubscribe turns them off", %{conn: conn, member: member} do
    conn = post(conn, ReplyLinks.reminders_path(member), %{"List-Unsubscribe" => "One-Click"})

    assert response(conn, 200) =~ "Invitation reminders are off."
    assert %Member{invitation_reminders: false} = Repo.reload(member)
    assert build_conn() |> post("/reminders/made-up") |> response(404)
  end

  describe "logged in" do
    # A team admin of 2 teams, who last opened the other one.
    setup %{conn: conn, member: member} do
      other = team_fixture(%{name: "Alpine SAR"})
      manager_fixture(Repo.preload(member, :team).team, %{email: "alex@example.com"})
      manager_fixture(other, %{email: "alex@example.com"})
      user = App.AccountsFixtures.user_fixture(%{email: "alex@example.com"})
      user = user |> Ecto.Changeset.change(last_team_id: other.id) |> Repo.update!()
      %{conn: log_in_user(conn, user)}
    end

    test "the bar names the link's team, and account settings need no login",
         %{conn: conn, member: member} do
      {:ok, lv, _html} = live(conn, ReplyLinks.reminders_path(member))
      assert has_element?(lv, "#nav-area", "Coast Range SAR")

      lv |> element("#reminders-off") |> render_click()
      assert has_element?(lv, "#reminders-account", "Open account settings")
      refute has_element?(lv, "#reminders-account + .hint")
    end

    test "a bad link opens account settings, not Log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/reminders/made-up")

      assert has_element?(lv, ~s{#reminders-account[href="/account"]}, "Open account settings")
      refute has_element?(lv, "#reminders-login")
    end
  end
end
