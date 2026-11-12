defmodule Web.PhotoAddLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  # cspell:ignore Noor -- Noor Aziz, of the Coast Range SAR cast
  # Add photos from Photos (#1033): which activity? It lists the ones the person may
  # add to, newest first, and opens the one picked.
  setup %{conn: conn} do
    team = member_logins_team_fixture(%{name: "Coast Range SAR", photos_enabled: true})
    admin = user_fixture()
    manager_fixture(team, %{email: admin.email, name: "Alex Chen"})
    cam = member_fixture(team, %{name: "Cameron Ruiz", d4h_permission: 2})
    noor = member_fixture(team, %{name: "Noor Aziz", d4h_permission: 2})
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    activity = fn title, days, attrs ->
      started_at = DateTime.add(now, days, :day)

      activity_fixture(
        team,
        Map.merge(
          %{title: title, started_at: started_at, finished_at: DateTime.add(started_at, 2, :hour)},
          attrs
        )
      )
    end

    swiftwater = activity.("Swiftwater training", -7, %{started_at: ~U[2026-10-28 02:00:00Z]})
    night = activity.("Night search exercise", -1, %{})
    rope = activity.("Rope rescue training", -3, %{})
    incident = activity.("Missing hiker", -2, %{activity_kind: "incident"})
    for attended <- [swiftwater, night, incident], do: attendance_fixture(attended, cam)

    %{
      conn: conn,
      team: team,
      admin: admin,
      cam: cam,
      noor: noor,
      swiftwater: swiftwater,
      night: night,
      rope: rope
    }
  end

  # Logged in as the member: their email is their login.
  defp as(conn, %{email: email}),
    do: log_in_user(conn, App.Accounts.get_user_by_email(email) || user_fixture(%{email: email}))

  defp options(lv) do
    lv
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("select[name=activity_id] option")
    |> Enum.map(&String.trim(Floki.text(&1)))
    |> Enum.reject(&(&1 in ["", "Select an activity"]))
  end

  test "a member picks from the exercises and events they attended, newest first", ctx do
    {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(~p"/teams/#{ctx.team}/photos/new")

    assert has_element?(lv, "h1", "Add photos")
    assert has_element?(lv, ~s|label[for="photos-activity"]|, "Activity")
    assert render(lv) =~ "The exercises and events you attended."

    assert [night, "Swiftwater training · Oct 27, 2026"] = options(lv)
    assert night =~ "Night search exercise · "

    cancel = ~p"/teams/#{ctx.team}/photos"
    assert has_element?(lv, ~s|#photos-activity-cancel[href="#{cancel}"]|, "Cancel")
  end

  test "picking one opens its Add photos page", ctx do
    {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(~p"/teams/#{ctx.team}/photos/new")

    lv
    |> form("#photos-activity-form")
    |> render_change(%{"activity_id" => to_string(ctx.night.id)})

    assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{ctx.night.id}/photos/new")
  end

  test "an activity the box did not list opens nothing", ctx do
    {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(~p"/teams/#{ctx.team}/photos/new")

    # Rope rescue training, which Cameron did not attend.
    render_hook(lv, "pick", %{"activity_id" => to_string(ctx.rope.id)})
    render_hook(lv, "pick", %{"activity_id" => ""})

    assert has_element?(lv, "h1", "Add photos")
  end

  test "a team admin picks from every exercise and event that has started", ctx do
    {:ok, lv, _html} = ctx.conn |> log_in_user(ctx.admin) |> live(~p"/teams/#{ctx.team}/photos/new")

    assert render(lv) =~ "Every exercise and event that has started."

    assert ["Night search exercise" <> _, "Rope rescue training" <> _, "Swiftwater training" <> _] =
             options(lv)
  end

  test "with no activity to add to, the page is not found", ctx do
    assert_raise Web.Status.NotFound, fn ->
      ctx.conn |> as(ctx.noor) |> live(~p"/teams/#{ctx.team}/photos/new")
    end
  end
end
