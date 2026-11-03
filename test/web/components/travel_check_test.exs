defmodule Web.Components.TravelCheckTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
  alias App.Model.Attendance
  alias App.Model.Trip
  alias App.Operation.SetTravel
  alias App.Repo

  # Cameron drove to the ICP, set by Alex, a team admin. Cameron's home is 31 km one way
  # from the activity and 15 from the yard (the fixtures put the activity at 49.1,-123.1
  # and the yard at 49.2,-123.1).
  setup %{conn: conn} do
    %{team: team, member: cameron, user: user} =
      member_with_login_fixture(%{name: "Cameron Ruiz"})

    alex = manager_fixture(team, %{name: "Alex Chen"})
    alex_user = AccountsFixtures.user_fixture(%{email: alex.email})
    started_at = DateTime.utc_now() |> DateTime.add(-3, :day) |> DateTime.truncate(:second)
    activity = activity_fixture(team, %{title: "Missing hiker", started_at: started_at})
    row = attendance_fixture(activity, cameron)

    trip =
      Repo.insert!(%Trip{
        team_id: team.id,
        activity_id: activity.id,
        member_id: cameron.id,
        d4h_attendance_id: row.d4h_attendance_id,
        travel: "icp",
        km: 62,
        set_by_user_id: alex_user.id
      })

    Req.Test.stub(App.Adapter.Mapbox, fn conn ->
      cond do
        String.contains?(conn.request_path, "geocoding/") ->
          Req.Test.json(conn, %{"features" => [%{"center" => [-123.0, 49.25]}]})

        String.contains?(conn.request_path, "-123.1,49.1;") ->
          Req.Test.json(conn, %{"routes" => [%{"distance" => 31_000, "duration" => 1800}]})

        true ->
          Req.Test.json(conn, %{"routes" => [%{"distance" => 15_000, "duration" => 900}]})
      end
    end)

    %{
      conn: log_in_user(conn, user),
      team: team,
      activity: activity,
      trip: trip,
      alex: alex,
      alex_user: alex_user,
      cameron: cameron
    }
  end

  defp open(ctx) do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
    lv
  end

  defp trip, do: Repo.one!(Trip)

  test "the member sees who set it, and That's right checks it", ctx do
    lv = open(ctx)

    assert lv |> element("#activity-your-travel") |> render() =~
             "Alex Chen set it: drove to the ICP, 62 km there and back from home."

    lv |> element("#activity-your-travel-right-#{ctx.trip.d4h_attendance_id}") |> render_click()

    assert render(lv) =~ "Saved your travel."
    assert trip().checked_at

    assert lv |> element("#activity-your-travel") |> render() =~
             "Drove to the ICP, 62 km there and back from home. Checked."
  end

  test "Change offers the four choices with the member's own km, and saves theirs", ctx do
    lv = open(ctx)
    lv |> element("#activity-your-travel-change-#{ctx.trip.d4h_attendance_id}") |> render_click()

    form = lv |> element("#activity-your-travel-form") |> render()
    assert form =~ "Drove to the ICP, 62 km"
    assert form =~ "Drove to the yard, 30 km"
    assert form =~ "Passenger, 0 km"

    lv
    |> form("#activity-your-travel-form", %{"travel" => "other", "km" => "140"})
    |> render_submit()

    assert %Trip{travel: "other", km: 140, checked_at: %DateTime{}} = trip()
  end

  test "the Dashboard asks until it's checked", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")

    assert lv |> element("#to-do-travel-#{ctx.activity.id}") |> render() =~
             "Check your travel for Missing hiker"

    assert lv |> element("#to-do-travel-#{ctx.activity.id}") |> render() =~
             "Drove to the ICP, 62 km."

    Trip.check!(trip(), DateTime.utc_now())
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")
    refute has_element?(lv, "#to-do-travel-#{ctx.activity.id}")
  end

  test "once published, it shows with nothing to change, and the Dashboard stops asking", ctx do
    ctx.activity |> Ecto.Changeset.change(is_published: true) |> Repo.update!()
    lv = open(ctx)

    assert lv |> element("#activity-your-travel") |> render() =~
             "Published, so travel can&#39;t be changed."

    refute has_element?(lv, "#activity-your-travel-right-#{ctx.trip.d4h_attendance_id}")

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")
    refute has_element?(lv, "#to-do-travel-#{ctx.activity.id}")
  end

  test "a team admin viewing as the member saves nothing", ctx do
    conn =
      build_conn()
      |> log_in_user(ctx.alex_user)
      |> post(~p"/teams/#{ctx.team}/members/#{ctx.cameron}/view-as")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")

    lv |> element("#activity-your-travel-right-#{ctx.trip.d4h_attendance_id}") |> render_click()

    refute trip().checked_at
  end

  test "a team admin setting it again asks the member to check again", ctx do
    Trip.check!(trip(), DateTime.utc_now())
    [row] = Repo.all(Attendance)

    {:ok, _plan} =
      SetTravel.call(
        ctx.team,
        ctx.activity,
        ctx.alex_user,
        [row.id],
        "passenger",
        "",
        DateTime.utc_now()
      )

    assert %Trip{travel: "passenger", km: 0, checked_at: nil} = trip()
  end
end
