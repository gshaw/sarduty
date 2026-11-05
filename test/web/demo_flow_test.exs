defmodule Web.DemoFlowTest do
  # Try a demo (#857), from the button or the API to the delete. The build itself runs
  # against a throwaway Records in sarduty-records' bin/check-sarduty; here Records is
  # stubbed.
  use Web.ConnCase
  use Oban.Testing, repo: App.Repo, engine: Oban.Engines.Lite

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Accounts
  alias App.Accounts.User
  alias App.Model.DemoTeam
  alias App.Model.OutboxMessage
  alias App.Model.Team
  alias App.Operation.CreateDemo
  alias App.RecordsStub
  alias App.Repo
  alias App.Worker.DemoTeamsWorker
  alias App.Worker.ScheduleTeamSyncsWorker
  alias App.Worker.SyncTeamChangesWorker

  setup do
    Application.put_env(:sarduty, :records_demo_key, "demo-key")
    Application.put_env(:sarduty, :demo_test_key, "test-key")

    on_exit(fn ->
      Application.delete_env(:sarduty, :records_demo_key)
      Application.delete_env(:sarduty, :demo_test_key)
    end)

    :ok
  end

  defp ip, do: "10.7.#{System.unique_integer([:positive])}"

  defp start!(params \\ %{"name" => "Morgan Visitor"}) do
    {:ok, demo} = CreateDemo.call(params, ip: ip())
    demo
  end

  defp link(demo), do: ~p"/demo/open/#{DemoTeam.link_token(demo)}"

  defp built_demo(attrs \\ %{}) do
    team = team_fixture()
    demo = start!()
    user = Repo.get!(User, demo.user_id)
    manager_fixture(team, %{email: user.email})
    member_fixture(team, %{name: "Cameron Ruiz"})

    demo =
      demo
      |> Ecto.Changeset.change(Map.merge(%{team_id: team.id}, attrs))
      |> Repo.update!()

    %{user: user, team: team, demo: demo}
  end

  test "the home page offers Try a demo once Records' demo key is set", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, "#start-top-demo", "Try a demo")

    Application.delete_env(:sarduty, :records_demo_key)
    {:ok, lv, _html} = live(conn, ~p"/")
    refute has_element?(lv, "#start-top-demo")
  end

  test "the home page offers Try a demo when logged in too", %{conn: conn} do
    user = user_fixture()
    team = team_fixture()
    manager_fixture(team, %{email: user.email})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/")
    assert has_element?(lv, "#start-top a", team.name)
    assert has_element?(lv, "#start-top-demo", "Try a demo")
  end

  test "/demo warns a logged-in user that a demo logs them out", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/demo")
    refute has_element?(lv, "#demo-logged-in")
    assert has_element?(lv, "#demo-start", "Start a demo")

    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/demo")
    assert has_element?(lv, "#demo-logged-in", user.email)
    assert has_element?(lv, "#demo-logged-in", "private window")
    assert has_element?(lv, "#demo-start", "Log out and start a demo")
  end

  test "the button starts a demo and opens its link, with no email", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/demo")

    assert {:error, {:redirect, %{to: "/demo/open/" <> _token = to}}} =
             lv
             |> form("#demo-form", demo_start_view_model: %{name: "Morgan Visitor"})
             |> render_submit()

    refute_email_sent()

    demo = Repo.one!(DemoTeam)
    assert %DemoTeam{kind: :visitor, name: "Morgan Visitor", team_id: nil} = demo
    assert Repo.get!(User, demo.user_id).email == "visitor-#{demo.id}@example.com"

    conn = get(conn, to)
    assert redirected_to(conn) == ~p"/demo/building"
  end

  test "the name is optional, and a blank one gives the member a made-up name" do
    demo = start!(%{"name" => ""})
    assert DemoTeam.visitor_name(demo) == "Taylor Brooks"
  end

  test "the link logs in and builds; a failed build keeps nothing and offers Try again", %{
    conn: conn
  } do
    demo = start!()
    RecordsStub.stub(fn _method, _path, _body -> {500, %{"title" => "Down"}} end)

    conn = get(conn, link(demo))
    assert redirected_to(conn) == ~p"/demo/building"
    assert conn.resp_cookies["_sarduty_remember_me"]

    {:ok, lv, _html} = conn |> recycle() |> live(~p"/demo/building")
    assert render(lv) =~ "did not build"
    assert has_element?(lv, "#demo-retry")
    assert Repo.reload!(demo).team_id == nil
  end

  test "a forged, expired, or deleted demo's link goes back to /demo", %{conn: conn} do
    demo = start!()
    past = DateTime.utc_now(:second) |> DateTime.add(-1, :minute)

    for path <- [~p"/demo/open/forged", link(demo)] do
      demo |> Ecto.Changeset.change(expires_at: past) |> Repo.update!()
      conn = get(conn, path)
      assert redirected_to(conn) == ~p"/demo"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "ended or was deleted"
    end
  end

  test "5 demos an hour per IP" do
    ip = ip()
    for _n <- 1..5, do: assert({:ok, _demo} = CreateDemo.call(%{}, ip: ip))
    assert CreateDemo.call(%{}, ip: ip) == {:error, :limited}
  end

  test "200 live visitors' demos in all; test demos don't count" do
    now = DateTime.utc_now(:second)
    expires = DateTime.add(now, 1, :day)

    Repo.insert_all(
      DemoTeam,
      for(
        _n <- 1..200,
        do: %{kind: :visitor, expires_at: expires, inserted_at: now, updated_at: now}
      )
    )

    assert CreateDemo.call(%{}, ip: ip()) == {:error, :full}
    assert {:ok, %DemoTeam{kind: :test}} = CreateDemo.call(%{}, kind: :test)
  end

  describe "the API" do
    test "POST /api/demos answers the link", %{conn: conn} do
      conn = post(conn, ~p"/api/demos", %{name: "Morgan Visitor"})

      assert %{"url" => url, "kind" => "visitor", "expires_at" => _} = json_response(conn, 201)
      assert url =~ ~r"/demo/open/[\w.-]+$"
      assert Repo.one!(DemoTeam).name == "Morgan Visitor"
    end

    test "the test key makes a test demo for the hours asked, 24 at most", %{conn: conn} do
      for {hours, expect} <- [{nil, 2}, {"6", 6}, {"100", 24}] do
        conn =
          conn
          |> put_req_header("authorization", "Bearer test-key")
          |> post(~p"/api/demos", %{hours: hours})

        assert %{"kind" => "test", "expires_at" => expires_at} = json_response(conn, 201)
        {:ok, expires_at, 0} = DateTime.from_iso8601(expires_at)
        assert_in_delta DateTime.diff(expires_at, DateTime.utc_now(), :hour), expect, 1
      end
    end

    test "a wrong key makes a visitor's demo", %{conn: conn} do
      conn = conn |> put_req_header("authorization", "Bearer nope") |> post(~p"/api/demos")
      assert %{"kind" => "visitor"} = json_response(conn, 201)
    end

    test "the limits answer 429 and 503", %{conn: conn} do
      conn = put_req_header(conn, "fly-client-ip", ip())
      for _n <- 1..5, do: post(conn, ~p"/api/demos")

      assert %{"error" => "Too many demos" <> _} =
               conn |> post(~p"/api/demos") |> json_response(429)

      Application.delete_env(:sarduty, :records_demo_key)

      assert %{"error" => "Try a demo is off" <> _} =
               build_conn() |> post(~p"/api/demos") |> json_response(503)
    end

    test "DELETE /api/demos/:token deletes the demo", %{conn: conn} do
      demo = start!()
      token = DemoTeam.link_token(demo)

      assert conn |> delete(~p"/api/demos/#{token}") |> response(204)
      refute Repo.reload(demo)
      refute Repo.get(User, demo.user_id)
      assert conn |> delete(~p"/api/demos/#{token}") |> json_response(404)
    end
  end

  test "a built demo opens its Dashboard, with the banner, its link, and its Outbox", %{
    conn: conn
  } do
    %{user: user, team: team, demo: demo} = built_demo()
    conn = log_in_user(conn, user)

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/demo/building")
    assert to == ~p"/teams/#{team}"

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
    assert has_element?(lv, "#demo-banner")
    assert has_element?(lv, "#demo-link-copy[value*='/demo/open/']")
    refute has_element?(lv, "#demo-link a")
    assert has_element?(lv, "#demo-outbox", "Outbox (0)")
    refute has_element?(lv, "#demo-view-as")
    refute has_element?(lv, "#demo-signup")
    assert has_element?(lv, "#demo-delete[data-confirm]")
    assert Repo.reload!(demo).seen_at
  end

  test "the Outbox lists a demo's email, shows it, and serves its HTML sandboxed", %{
    conn: conn
  } do
    %{user: user, team: team} = built_demo()
    conn = log_in_user(conn, user)

    message =
      [
        to: {"Cameron Ruiz", "cameron@example.com"},
        subject: "Will you be there? Training night",
        text_body: "Reply: https://sarduty.com/replies/abc",
        html_body: "<p>Reply</p>"
      ]
      |> Swoosh.Email.new()
      |> OutboxMessage.add_email!(team.id)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/outbox")
    assert has_element?(lv, "#outbox-message-#{message.id}", "Training night")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/outbox/#{message.id}")
    assert has_element?(lv, "#outbox-to", "Cameron Ruiz")
    assert has_element?(lv, ~s|#outbox-body a[href="https://sarduty.com/replies/abc"]|)
    assert has_element?(lv, "iframe#outbox-html[sandbox]")

    conn = get(conn, ~p"/teams/#{team}/outbox/#{message.id}/html")
    assert html_response(conn, 200) == "<p>Reply</p>"
    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "sandbox"
  end

  test "another demo's message 404s in this demo's Outbox", %{conn: conn} do
    %{user: user, team: team} = built_demo()
    %{team: other} = built_demo()

    theirs =
      [to: "a@example.com", html_body: "<p>x</p>"]
      |> Swoosh.Email.new()
      |> OutboxMessage.add_email!(other.id)

    conn = log_in_user(conn, user)

    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/outbox/#{theirs.id}") end
    assert_error_sent 404, fn -> get(conn, ~p"/teams/#{team}/outbox/#{theirs.id}/html") end
  end

  test "a real team has no demo banner and no Outbox", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
    refute has_element?(lv, "#demo-banner")
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/outbox") end
  end

  test "Delete this demo deletes it in SAR Duty and Records, with its user, and logs out", %{
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

  test "the hourly job deletes demos past their time, built or never opened" do
    %{team: team, demo: demo} = built_demo()
    unopened = start!()
    RecordsStub.stub(fn "DELETE", _path, _body -> {200, %{}} end)

    :ok = DateTime.utc_now(:second) |> DateTime.add(2, :day) |> DemoTeamsWorker.run()
    assert Repo.get(Team, team.id)

    :ok = DateTime.utc_now(:second) |> DateTime.add(4, :day) |> DemoTeamsWorker.run()
    refute Repo.get(Team, team.id)
    refute Repo.reload(demo)
    refute Repo.reload(unopened)
  end

  test "the 10-minute sync takes a demo only while someone has it open" do
    now = DateTime.utc_now(:second)
    %{team: team} = built_demo(%{seen_at: DateTime.add(now, -2, :hour)})
    team |> Ecto.Changeset.change(d4h_team_id: 1, d4h_access_key: "key") |> Repo.update!()

    synced? = fn ->
      Oban.Testing.with_testing_mode(:manual, fn ->
        :ok = ScheduleTeamSyncsWorker.perform(%Oban.Job{})

        [worker: SyncTeamChangesWorker]
        |> all_enqueued()
        |> Enum.any?(&(&1.args["team_id"] == team.id))
      end)
    end

    refute synced?.()
    team |> DemoTeam.for_team() |> DemoTeam.seen!(now)
    assert synced?.()
  end
end
