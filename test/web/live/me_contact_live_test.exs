defmodule Web.MeContactLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Accounts
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Repo

  setup %{conn: conn} do
    %{team: team, member: member, user: user} =
      member_with_login_fixture(%{email: "old@example.com", phone: "604-555-0100"})

    team = team |> Ecto.Changeset.change(d4h_access_key: "key") |> Repo.update!()
    member = %{member | team: team}
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  # D4H takes any PATCH; each body comes to the test process.
  defp stub_d4h(team, member) do
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:patch, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "id" => member.d4h_member_id,
        "name" => member.name,
        "owner" => %{"resourceType" => "Team", "id" => team.d4h_team_id},
        "email" => %{"value" => "new@example.com"},
        "mobile" => %{"phone" => nil}
      })
    end)
  end

  defp email_code do
    receive do
      {:email, %{subject: "Your SAR Duty confirmation code: " <> code}} -> code
    after
      0 -> flunk("no confirmation code was emailed")
    end
  end

  defp confirm(conn, team, sent_to, code),
    do:
      post(conn, ~p"/teams/#{team}/me/contact/confirm", confirm: %{sent_to: sent_to, code: code})

  describe "a new email" do
    test "is confirmed by a code sent to it, then changes D4H and moves the login",
         %{conn: conn, team: team, member: member, user: user} do
      stub_d4h(team, member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/contact")

      lv |> form("#email-form", email: %{email: "New@Example.com"}) |> render_submit()

      assert has_element?(lv, "#code-sent", "new@example.com")
      assert_received {:email, %{to: [{"", "new@example.com"}]} = sent}
      "Your SAR Duty confirmation code: " <> code = sent.subject
      refute_received {:patch, _body}

      conn = confirm(conn, team, "new@example.com", code)

      assert redirected_to(conn) == ~p"/teams/#{team}/me"
      assert_received {:patch, %{"email" => "new@example.com"}}
      assert Repo.reload!(member).email == "new@example.com"

      [change_set] = Repo.all(ChangeSet)
      assert {change_set.source, change_set.proposed_by_user_id} == {:member, user.id}
      assert [%ChangeSetRow{status: :applied}] = Repo.all(ChangeSetRow)

      assert_received {:email, %{to: [{"", "old@example.com"}], subject: subject}}
      assert subject =~ "Your email on #{team.name} changed"

      new_user = Accounts.get_user_by_email("new@example.com")
      assert new_user.id != user.id
      token = get_session(conn, :user_token)
      assert Accounts.get_user_by_session_token(token).id == new_user.id
    end

    test "a wrong code changes nothing", %{conn: conn, team: team, member: member} do
      stub_d4h(team, member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/contact")
      lv |> form("#email-form", email: %{email: "new@example.com"}) |> render_submit()
      code = email_code()
      wrong = if code == "000000", do: "111111", else: "000000"

      conn = confirm(conn, team, "new@example.com", wrong)

      assert redirected_to(conn) == ~p"/teams/#{team}/me/contact"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "wrong or expired"
      refute_received {:patch, _body}
      assert Repo.reload!(member).email == "old@example.com"
    end

    test "a code works only for the email it went to", %{conn: conn, team: team, member: member} do
      stub_d4h(team, member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/contact")
      lv |> form("#email-form", email: %{email: "new@example.com"}) |> render_submit()
      code = email_code()

      confirm(conn, team, "other@example.com", code)

      refute_received {:patch, _body}
    end

    test "can't be another member's on the team", %{conn: conn, team: team} do
      member_fixture(team, %{email: "taken@example.com"})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/contact")

      html = lv |> form("#email-form", email: %{email: "taken@example.com"}) |> render_submit()

      assert html =~ "Another member of your team has that email"
      refute_received {:email, _email}
    end

    test "a waiting code shows its form after a reload, and cancel drops it",
         %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/contact")
      lv |> form("#email-form", email: %{email: "new@example.com"}) |> render_submit()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/contact")
      assert has_element?(lv, "#code-form")

      lv |> element("#cancel-code") |> render_click()
      assert has_element?(lv, "#email-form")
    end
  end

  describe "a new mobile number" do
    test "is confirmed by a text, then changes D4H", %{conn: conn, team: team, member: member} do
      text_login_fixture()
      stub_d4h(team, member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/contact")

      lv |> form("#phone-form", phone: %{phone: "(604) 555-0199"}) |> render_submit()

      assert_received {:text, "+16045550199", "Your SAR Duty confirmation code: " <> rest}
      <<code::binary-6, _rest::binary>> = rest

      conn = confirm(conn, team, "+16045550199", code)

      assert redirected_to(conn) == ~p"/teams/#{team}/me"
      assert_received {:patch, %{"phone" => %{"mobile" => "604-555-0199"}}}
      assert Repo.reload!(member).phone == "604-555-0199"
      assert_received {:email, %{to: [{"", "old@example.com"}], subject: subject}}
      assert subject =~ "mobile number"
    end

    test "can't be changed while texts are off", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/contact")
      refute has_element?(lv, "#phone-form")
      assert has_element?(lv, "#phone-off")
    end
  end

  test "the confirm post is a 404 for someone not a member there", %{conn: conn} do
    other = member_logins_team_fixture()

    assert_error_sent 404, fn ->
      confirm(conn, other, "new@example.com", "123456")
    end
  end
end
