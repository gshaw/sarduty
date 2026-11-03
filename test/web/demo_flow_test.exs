defmodule Web.DemoFlowTest do
  # Try a demo (#857), from the home page to the delete. The build itself runs against a
  # throwaway Records in sarduty-records' bin/check-sarduty; here Records is stubbed.
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Accounts
  alias App.Model.DemoTeam
  alias App.Model.Team
  alias App.Operation.RequestDemo
  alias App.RecordsStub
  alias App.Repo
  alias App.Worker.DemoTeamsWorker

  setup do
    Application.put_env(:sarduty, :records_demo_key, "demo-key")
    on_exit(fn -> Application.delete_env(:sarduty, :records_demo_key) end)
    :ok
  end

  defp code_from(email) do
    [code] = Regex.run(~r/\d{6}$/, email.subject)
    code
  end

  defp request!(email \\ "morgan@example.com", ip \\ "10.7.#{System.unique_integer([:positive])}") do
    {:ok, demo} = RequestDemo.call(%{"name" => "Morgan Visitor", "email" => email}, ip)
    assert_received {:email, sent}
    {demo, code_from(sent), sent}
  end

  defp built_demo do
    %{user: user, team: team} = user_with_team_fixture()
    demo = demo_team_fixture(team, %{email: user.email})
    member_fixture(team, %{name: "Cameron Ruiz"})
    %{user: user, team: team, demo: demo}
  end

  test "the home page offers Try a demo once Records' demo key is set", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, "#start-top-demo", "Try a demo")

    Application.delete_env(:sarduty, :records_demo_key)
    {:ok, lv, _html} = live(conn, ~p"/")
    refute has_element?(lv, "#start-top-demo")
  end

  test "the form emails a link and a code, with no name in it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/demo")

    lv
    |> form("#demo-form",
      demo_request_view_model: %{name: "Morgan <b>Visitor</b>", email: "Morgan@Example.com"}
    )
    |> render_submit()

    assert has_element?(lv, "#demo-sent", "morgan@example.com")
    assert has_element?(lv, "#code-form")

    assert_email_sent(fn email ->
      assert email.to == [{"", "morgan@example.com"}]
      assert email.text_body =~ ~r"/demo/open/\d+\?code=\d{6}"
      refute email.text_body =~ "Morgan"
      refute email.html_body =~ "Morgan"
      true
    end)

    assert %DemoTeam{name: "Morgan <b>Visitor</b>", team_id: nil} =
             DemoTeam.get_by_email("morgan@example.com")
  end

  test "one demo per email: asking again sends a new code for the same demo" do
    {demo, first, _sent} = request!()
    {again, second, _sent} = request!()

    assert again.id == demo.id

    now = DateTime.utc_now(:second)
    if first != second, do: refute(demo |> Repo.reload!() |> DemoTeam.code_ok?(first, now))
    assert demo |> Repo.reload!() |> DemoTeam.code_ok?(second, now)
  end

  test "5 requests an hour per IP" do
    ip = "10.8.#{System.unique_integer([:positive])}"
    for n <- 1..5, do: request!("visitor#{n}@example.com", ip)

    assert RequestDemo.call(%{"name" => "Sixth", "email" => "six@example.com"}, ip) ==
             {:error, :limited}
  end

  test "200 live demos in all" do
    now = DateTime.utc_now(:second)
    expires = DateTime.add(now, 1, :day)

    Repo.insert_all(
      DemoTeam,
      for(
        n <- 1..200,
        do: %{
          name: "V",
          email: "v#{n}@example.com",
          expires_at: expires,
          inserted_at: now,
          updated_at: now
        }
      )
    )

    assert RequestDemo.call(%{"name" => "Late", "email" => "late@example.com"}, "10.9.9.9") ==
             {:error, :full}
  end

  test "the link logs in and builds; a failed build keeps nothing and offers Try again", %{
    conn: conn
  } do
    {demo, code, _sent} = request!()
    RecordsStub.stub(fn _method, _path, _body -> {500, %{"title" => "Down"}} end)

    conn = get(conn, ~p"/demo/open/#{demo.id}?#{[code: code]}")
    assert redirected_to(conn) == ~p"/demo/building"
    assert Accounts.get_user_by_email("morgan@example.com")

    {:ok, lv, _html} = conn |> recycle() |> live(~p"/demo/building")
    assert render(lv) =~ "did not build"
    assert has_element?(lv, "#demo-retry")
    assert Repo.reload!(demo).team_id == nil
  end

  test "a wrong code goes back to the form, and 5 misses kill it", %{conn: conn} do
    {demo, code, _sent} = request!()

    for _ <- 1..5 do
      conn = get(conn, ~p"/demo/open/#{demo.id}?#{[code: "000000"]}")
      assert redirected_to(conn) == ~p"/demo?#{[error: "code"]}"
    end

    conn = get(conn, ~p"/demo/open/#{demo.id}?#{[code: code]}")
    assert redirected_to(conn) == ~p"/demo?#{[error: "code"]}"
  end

  test "the code step: blank and wrong codes stay on it, and a refresh keeps it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/demo")

    lv
    |> form("#demo-form", demo_request_view_model: %{name: "Morgan", email: "morgan@example.com"})
    |> render_submit()

    assert_received {:email, sent}
    code = code_from(sent)
    path = assert_patch(lv)
    assert path =~ ~r"^/demo\?sent="

    lv |> form("#code-form", demo: %{code: ""}) |> render_submit()
    assert has_element?(lv, "#code-form", "Enter the 6-digit code")

    lv |> form("#code-form", demo: %{code: "000000"}) |> render_submit()
    assert has_element?(lv, "#code-form", "That code is not right")

    {:ok, lv, _html} = live(conn, path)
    assert has_element?(lv, "#demo-sent", "morgan@example.com")

    demo = DemoTeam.get_by_email("morgan@example.com")
    form = form(lv, "#code-form", demo: %{id: demo.id, code: code})
    render_submit(form)
    conn = follow_trigger_action(form, conn)
    assert redirected_to(conn) == ~p"/demo/building"
  end

  test "5 wrong codes on the code step ask for a new one, which works", %{conn: conn} do
    {demo, _code, _sent} = request!()

    {:ok, lv, _html} =
      live(conn, "/demo?sent=" <> Phoenix.Token.sign(Web.Endpoint, "demo sent", demo.id))

    for _ <- 1..4, do: lv |> form("#code-form", demo: %{code: "000000"}) |> render_submit()
    assert has_element?(lv, "#code-form", "That code is not right")
    lv |> form("#code-form", demo: %{code: "000000"}) |> render_submit()
    assert has_element?(lv, "#code-form", "That code has expired")

    lv |> element("#demo-resend") |> render_click()
    assert_received {:email, sent}
    assert demo |> Repo.reload!() |> DemoTeam.code_ok?(code_from(sent), DateTime.utc_now(:second))
  end

  test "a forged or old code step goes back to the form", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/demo?#{[sent: "forged"]}")
    refute has_element?(lv, "#demo-sent")
    assert has_element?(lv, "#demo-form")
  end

  test "a built demo opens its Dashboard, with the banner", %{conn: conn} do
    %{user: user, team: team} = built_demo()
    conn = log_in_user(conn, user)

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/demo/building")
    assert to == ~p"/teams/#{team}"

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
    assert has_element?(lv, "#demo-banner")
    assert has_element?(lv, "#demo-view-as", "View as Cameron Ruiz")
    assert has_element?(lv, "#demo-delete[data-confirm]")
  end

  test "a real team has no demo banner", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}")
    refute has_element?(lv, "#demo-banner")
  end

  test "Delete this demo deletes it in SAR Duty and Records, with the user, and logs out", %{
    conn: conn
  } do
    %{user: user, team: team, demo: demo} = built_demo()
    RecordsStub.stub(fn "DELETE", _path, _body -> {200, %{}} end)

    conn = conn |> log_in_user(user) |> delete(~p"/teams/#{team}/demo")

    assert redirected_to(conn) == ~p"/"
    refute Repo.get(Team, team.id)
    refute Repo.reload(demo)
    refute Accounts.get_user_by_email(user.email)
    assert_received {:records, "DELETE", "/v3/demo/teams/" <> _, nil}
  end

  test "only the demo's visitor deletes it", %{conn: conn} do
    %{team: team} = built_demo()
    other = App.AccountsFixtures.user_fixture()
    manager_fixture(team, %{email: other.email})

    assert_raise Web.Status.NotFound, fn ->
      conn |> log_in_user(other) |> delete(~p"/teams/#{team}/demo")
    end

    assert Repo.get(Team, team.id)
  end

  test "the hourly job emails the day before, once, and deletes on day 7" do
    %{team: team, demo: demo} = built_demo()
    now = DateTime.utc_now(:second)

    demo =
      demo |> Ecto.Changeset.change(expires_at: DateTime.add(now, 20, :hour)) |> Repo.update!()

    :ok = DemoTeamsWorker.run(now)
    assert_email_sent(subject: "Your SAR Duty demo goes tomorrow")
    :ok = DemoTeamsWorker.run(now)
    refute_email_sent()

    RecordsStub.stub(fn "DELETE", _path, _body -> {200, %{}} end)
    :ok = now |> DateTime.add(21, :hour) |> DemoTeamsWorker.run()

    refute Repo.get(Team, team.id)
    refute Repo.reload(demo)
  end

  test "a demo never opened goes on day 7 too" do
    {demo, _code, _sent} = request!()
    :ok = DateTime.utc_now() |> DateTime.add(8, :day) |> DemoTeamsWorker.run()
    refute Repo.reload(demo)
  end
end
