defmodule Web.ActivityMileageLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.HomeCoordinate
  alias App.Repo

  test "redirects when not authenticated", %{conn: conn} do
    team = team_fixture(%{subdomain: "alpha"})

    assert {:error, redirect} = live(conn, ~p"/teams/#{team}/activities/1/mileage")

    assert {:redirect, %{to: path, flash: flash}} = redirect
    assert path == ~p"/login"
    assert %{"error" => "Log in to see this page."} = flash
  end

  # The team's yard is at 49.2,-123.1 and the activity at 49.1,-123.1 (the fixtures). Ann's
  # home is at 49.25,-123.0: 25 km one way from the activity, 40 km from the yard, and
  # anything else is 10 km.
  describe "from SAR Duty's copy (#230)" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      activity = activity_fixture(team)
      ann = member_fixture(team, %{name: "Ann Smith", address: "1 Home Rd"})
      bob = member_fixture(team, %{name: "Bob Jones", address: nil})
      attendance_fixture(activity, ann)
      attendance_fixture(activity, bob)
      stub_mapbox(self())
      %{conn: log_in_user(conn, user), team: team, activity: activity, ann: ann}
    end

    defp stub_mapbox(test) do
      Req.Test.stub(App.Adapter.Mapbox, fn conn ->
        path = URI.decode(conn.request_path)
        send(test, {:mapbox, path})

        cond do
          String.contains?(path, "geocoding/") ->
            Req.Test.json(conn, %{"features" => [%{"center" => [-123.0, 49.25]}]})

          String.ends_with?(path, "-123.1,49.1;-123.0,49.25") ->
            Req.Test.json(conn, %{"routes" => [%{"distance" => 25_000, "duration" => 1800}]})

          String.ends_with?(path, "-123.1,49.2;-123.0,49.25") ->
            Req.Test.json(conn, %{"routes" => [%{"distance" => 40_000, "duration" => 2700}]})

          true ->
            Req.Test.json(conn, %{"routes" => [%{"distance" => 10_000, "duration" => 600}]})
        end
      end)
    end

    defp open(ctx) do
      {:ok, lv, _html} =
        live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/mileage")

      render_async(lv)
      lv
    end

    defp mapbox_calls do
      receive do
        {:mapbox, path} -> [path | mapbox_calls()]
      after
        0 -> []
      end
    end

    test "each attended row's round trips, with no D4H call", ctx do
      # No D4H stub: a D4H call would fail the test.
      lv = open(ctx)

      assert lv |> element("#mileage_report") |> render() =~ "Ann Smith"
      assert lv |> element("#mileage_report") |> render() =~ "50 km"
      assert lv |> element("#mileage_report") |> render() =~ "80 km"
      assert lv |> element("#mileage_report") |> render() =~ "No home address in D4H."
      assert lv |> element("#yard-to-activity") |> render() =~ "20 km"
    end

    test "Mapbox is asked once: the next visit reads what was saved", ctx do
      open(ctx)
      assert length(mapbox_calls()) == 4

      lv = open(ctx)
      assert mapbox_calls() == []
      assert lv |> element("#mileage_report") |> render() =~ "50 km"
    end

    test "a changed address is looked up again", ctx do
      open(ctx)
      mapbox_calls()

      ctx.ann |> Ecto.Changeset.change(address: "2 New Rd") |> Repo.update!()
      open(ctx)

      assert Enum.count(mapbox_calls(), &String.contains?(&1, "geocoding/")) == 1
      assert Repo.get_by!(HomeCoordinate, member_id: ctx.ann.id).address == "2 New Rd"
    end

    test "a route Mapbox found none for is blank, and the page still shows", ctx do
      Req.Test.stub(App.Adapter.Mapbox, fn conn ->
        if String.contains?(conn.request_path, "geocoding/"),
          do: Req.Test.json(conn, %{"features" => [%{"center" => [-123.0, 49.25]}]}),
          else: Req.Test.json(conn, %{"routes" => []})
      end)

      lv = open(ctx)

      assert has_element?(lv, "#mileage_report")
      refute lv |> element("#mileage_report") |> render() =~ "km"
    end
  end
end
