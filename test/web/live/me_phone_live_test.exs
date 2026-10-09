defmodule Web.MePhoneLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Repo

  setup %{conn: conn} do
    %{team: team, member: member, user: user} =
      member_with_login_fixture(%{email: "member@example.com", phone: "604-555-0100"})

    team = team |> Ecto.Changeset.change(d4h_access_key: "key") |> Repo.update!()
    %{conn: log_in_user(conn, user), team: team, member: %{member | team: team}, user: user}
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
        "email" => %{"value" => member.email},
        "mobile" => %{"phone" => "604-555-0199"}
      })
    end)
  end

  defp send_code(lv, phone) do
    lv |> form("#phone-form", phone: %{phone: phone}) |> render_submit()

    receive do
      {:text, _to, "Your SAR Duty confirmation code: " <> <<code::binary-6, _rest::binary>>} ->
        code
    after
      0 -> flunk("no code was texted")
    end
  end

  test "a new number is confirmed by a text, then changes D4H",
       %{conn: conn, team: team, member: member, user: user} do
    text_login_fixture()
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/mobile")

    code = send_code(lv, "(604) 555-0199")
    assert has_element?(lv, "#code-sent", "604-555-0199")
    refute_received {:patch, _body}

    lv |> form("#code-form", confirm: %{code: code}) |> render_submit()

    assert_redirect(lv, ~p"/teams/#{team}/me")
    assert_received {:patch, %{"phone" => %{"mobile" => "604-555-0199"}}}
    assert Repo.reload!(member).phone == "604-555-0199"

    [change_set] = Repo.all(ChangeSet)
    assert {change_set.source, change_set.proposed_by_user_id} == {:member, user.id}
    assert [%ChangeSetRow{status: :applied}] = Repo.all(ChangeSetRow)

    assert_received {:email, %{to: [{"", "member@example.com"}], subject: subject}}
    assert subject =~ "Your mobile number on #{team.name} changed"
  end

  test "a wrong code changes nothing", %{conn: conn, team: team, member: member} do
    text_login_fixture()
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/mobile")
    code = send_code(lv, "604-555-0199")
    wrong = if code == "000000", do: "111111", else: "000000"

    html = lv |> form("#code-form", confirm: %{code: wrong}) |> render_submit()

    assert html =~ "wrong or expired"
    refute_received {:patch, _body}
    assert Repo.reload!(member).phone == "604-555-0100"
  end

  test "a waiting code shows its form after a reload, and cancel drops it",
       %{conn: conn, team: team} do
    text_login_fixture()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/mobile")
    send_code(lv, "604-555-0199")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/mobile")
    assert has_element?(lv, "#code-form")

    lv |> element("#cancel-code") |> render_click()
    assert has_element?(lv, "#phone-form")
  end

  test "the same number is refused", %{conn: conn, team: team} do
    text_login_fixture()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/mobile")

    html = lv |> form("#phone-form", phone: %{phone: "604-555-0100"}) |> render_submit()

    assert html =~ "That is your mobile number already."
    refute_received {:text, _to, _body}
  end

  test "can't be changed while texts are off", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/mobile")
    refute has_element?(lv, "#phone-form")
    assert has_element?(lv, "#phone-off")
  end

  test "the email shows, with no way to change it", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/mobile")
    assert has_element?(lv, "#email-note", "member@example.com")
    refute has_element?(lv, "input[type=email]")
  end
end
