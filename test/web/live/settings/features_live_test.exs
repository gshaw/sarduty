defmodule Web.Settings.FeaturesLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Accounts
  alias App.Model.Event
  alias App.Model.Team
  alias App.Model.WhiteboardNote
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    %{conn: log_in_user(conn, user), user: user, team: team}
  end

  defp open(conn, team), do: live(conn, ~p"/teams/#{team}/settings/features")
  defp flip(lv, feature), do: lv |> element("#feature-#{feature}") |> render_click()

  test "member logins are off until a team admin turns them on, and then members may log in",
       %{conn: conn, team: team} do
    member = member_fixture(team, %{d4h_permission: 2})
    refute Accounts.may_log_in?(member.email)

    {:ok, lv, _html} = open(conn, team)
    assert has_element?(lv, ".tabs a[aria-current=page]", "Features")
    refute has_element?(lv, "#feature-member-logins[checked]")

    flip(lv, "member-logins")
    assert Repo.reload!(team).member_logins
    assert Accounts.may_log_in?(member.email)
    assert Event.get_last(:member_logins_turned_on).team_id == team.id
    assert has_element?(lv, "#feature-member-logins[checked][data-confirm]")

    flip(lv, "member-logins")
    refute Repo.reload!(team).member_logins
    refute Accounts.may_log_in?(member.email)
  end

  test "chores and certificates wait on member logins, and keep their switch while it is off",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = open(conn, team)
    assert has_element?(lv, "#feature-chores[disabled]")
    assert has_element?(lv, "#feature-certificates[disabled]")

    flip(lv, "member-logins")
    flip(lv, "chores")
    assert team |> Repo.reload!() |> Team.chores?()
    assert has_element?(lv, ".tabs a", "Chore categories")
    assert has_element?(lv, "a[href='/teams/#{team.subdomain}/settings/chore-categories']")

    assert %{data: %{"feature" => "chores"}} = Event.get_last(:feature_turned_on)

    flip(lv, "certificates")
    assert team |> Repo.reload!() |> Team.certificates?()
    assert has_element?(lv, "#side-nav-certificates")

    flip(lv, "member-logins")
    team = Repo.reload!(team)
    refute Team.chores?(team)
    assert team.chores_enabled
    refute has_element?(lv, ".tabs a", "Chore categories")
  end

  describe "the whiteboard (#515)" do
    setup %{team: team} do
      team = team |> Ecto.Changeset.change(whiteboard_enabled: false) |> Repo.update!()
      %{team: team}
    end

    test "is off on a new team" do
      refute %Team{}.whiteboard_enabled
    end

    test "turning it on reads its notes from D4H", %{conn: conn, team: team} do
      note = %{
        "id" => 7,
        "text" => "Pager test Sunday.",
        "important" => false,
        "owner" => %{"resourceType" => "Team", "id" => 1},
        "archivedAt" => "2099-01-01T08:00:00Z",
        "createdAt" => "2026-10-20T16:00:00Z",
        "updatedAt" => "2026-10-20T16:00:00Z"
      }

      Req.Test.stub(App.Adapter.D4H, &Req.Test.json(&1, %{"results" => [note], "totalSize" => 1}))

      {:ok, lv, _html} = open(conn, team)
      flip(lv, "whiteboard")
      render_async(lv)

      team = Repo.reload!(team)
      assert Team.whiteboard?(team)
      assert [%{text: "Pager test Sunday."}] = WhiteboardNote.live(team, DateTime.utc_now())
      assert has_element?(lv, "#side-nav-whiteboard")
      refute has_element?(lv, "#whiteboard-off-in-d4h")
    end

    test "says so when D4H has the module off", %{conn: conn, team: team} do
      Req.Test.stub(App.Adapter.D4H, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"title" => "Forbidden"})
      end)

      {:ok, lv, _html} = open(conn, team)
      flip(lv, "whiteboard")
      render_async(lv)

      team = Repo.reload!(team)
      assert team.whiteboard_enabled
      refute Team.whiteboard?(team)
      assert has_element?(lv, "#whiteboard-off-in-d4h")
      refute has_element?(lv, "#side-nav-whiteboard")
    end
  end

  test "ID cards show as on or off, and MCP only once on, with no switch: SAR Duty turns them on",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = open(conn, team)
    assert has_element?(lv, "#feature-id-cards .badge", "On")
    refute has_element?(lv, "#feature-id-cards input")
    refute has_element?(lv, "#feature-mcp")

    team |> Ecto.Changeset.change(mcp_enabled: true) |> Repo.update!()
    {:ok, lv, _html} = open(conn, team)
    assert has_element?(lv, "#feature-mcp .badge", "On")
    refute has_element?(lv, "#feature-mcp input")
    assert has_element?(lv, "#feature-mcp a[href='/teams/#{team.subdomain}/settings/mcp']")
  end
end
