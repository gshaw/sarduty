defmodule Web.ActivityTravelLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Attendance
  alias App.Model.HomeCoordinate
  alias App.Model.Trip
  alias App.Repo

  test "redirects when not authenticated" do
    team = team_fixture(%{subdomain: "alpha"})

    assert {:error, redirect} = live(build_conn(), ~p"/teams/#{team}/activities/1/travel")

    assert {:redirect, %{to: path, flash: flash}} = redirect
    assert path == ~p"/login"
    assert %{"error" => "Log in to see this page."} = flash
  end

  # The team's yard is at 49.2,-123.1 and the activity at 49.1,-123.1 (the fixtures). Ann's
  # home is at 49.25,-123.0: 25 km one way from the activity, 40 km from the yard, and
  # anything else is 10 km. Bob has no address, so no route.
  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    started_at = DateTime.utc_now() |> DateTime.add(-3, :day) |> DateTime.truncate(:second)

    activity =
      activity_fixture(team, %{title: "Missing hiker", ref_id: "01472", started_at: started_at})

    ann = member_fixture(team, %{name: "Ann Smith", address: "1 Home Rd"})
    bob = member_fixture(team, %{name: "Bob Jones", address: nil})
    ann_row = attendance_fixture(activity, ann)
    bob_row = attendance_fixture(activity, bob)
    stub_mapbox(self())

    %{
      conn: log_in_user(conn, user),
      team: team,
      activity: activity,
      ann: ann,
      ann_row: ann_row,
      bob_row: bob_row
    }
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
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/travel")
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

  defp set(lv, row_ids, travel, km \\ "") do
    ids = Enum.map(row_ids, &to_string(&1.id))
    lv |> form("#travel-form", %{"row_ids" => ids, "km" => km}) |> render_change()

    lv
    |> form("#travel-form", %{"row_ids" => ids, "km" => km})
    |> render_submit(%{"travel" => travel})

    render_async(lv)
  end

  describe "round trips (#230)" do
    test "each attended row's round trips, with no D4H call", ctx do
      # No D4H stub: a D4H call would fail the test.
      lv = open(ctx)
      html = lv |> element("#travel-not-set") |> render()

      assert html =~ "Ann Smith"
      assert html =~ "50 km"
      assert html =~ "80 km"
      assert html =~ "No home address in D4H. Type their km."
    end

    test "Mapbox is asked once: the next visit reads what was saved", ctx do
      open(ctx)
      assert length(mapbox_calls()) == 4

      lv = open(ctx)
      assert mapbox_calls() == []
      assert lv |> element("#travel-not-set") |> render() =~ "50 km"
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

      assert has_element?(lv, "#travel-not-set")
      refute lv |> element("#travel-not-set") |> render() =~ ~r/\d km/
    end
  end

  describe "setting travel" do
    test "the checked rows go to the ICP at the saved round trip", ctx do
      lv = open(ctx)
      set(lv, [ctx.ann_row], "icp")

      assert render(lv) =~ "1 row set to ICP."
      assert lv |> element("#travel-set") |> render() =~ "Drove to the ICP"
      assert lv |> element("#travel-set") |> render() =~ "50 km"

      assert %Trip{travel: "icp", km: 50} =
               Repo.get_by!(Trip, d4h_attendance_id: ctx.ann_row.d4h_attendance_id)
    end

    test "a row with no route is skipped, then typed km sets it", ctx do
      lv = open(ctx)
      set(lv, [ctx.ann_row, ctx.bob_row], "yard")

      # The toast's first sentence is its title.
      assert render(lv) =~ "1 row set to yard."
      assert render(lv) =~ "No route from Bob Jones&#39;s home to the yard, so type their km."
      assert lv |> element("#travel-not-set") |> render() =~ "Bob Jones"

      set(lv, [ctx.bob_row], "other", "140")

      assert render(lv) =~ "1 row set to 140 km."
      refute has_element?(lv, "#travel-not-set")

      assert %Trip{travel: "other", km: 140} =
               Repo.get_by!(Trip, d4h_attendance_id: ctx.bob_row.d4h_attendance_id)
    end

    test "the buttons count the checked rows", ctx do
      lv = open(ctx)
      ids = [to_string(ctx.ann_row.id), to_string(ctx.bob_row.id)]
      lv |> form("#travel-form", %{"row_ids" => ids, "km" => "90"}) |> render_change()

      assert lv |> element("#travel-set-icp") |> render() =~ "Set 2 to ICP"
      assert lv |> element("#travel-set-other") |> render() =~ "Set 2 to 90 km"
    end

    test "the copy for D4H is folded away, names the activity, and lists the rows set", ctx do
      lv = open(ctx)
      refute has_element?(lv, "#travel-d4h")

      set(lv, [ctx.ann_row], "passenger")

      assert has_element?(lv, "details#travel-d4h:not([open])")
      prompt = lv |> element("#travel-d4h-prompt") |> render()
      assert prompt =~ ~s(activity 01472, &quot;Missing hiker&quot;)
      assert prompt =~ "Ann Smith | "
      assert prompt =~ " | 0\n"
      assert prompt =~ "Leave the Mileage km box alone on these rows:\nBob Jones | "
    end

    test "a published activity's travel can't change", ctx do
      ctx.activity |> Ecto.Changeset.change(is_published: true) |> Repo.update!()
      lv = open(ctx)

      assert has_element?(lv, "#travel-locked")
      refute has_element?(lv, "#travel-set-icp")
      refute has_element?(lv, "#travel-select-#{ctx.ann_row.id}")

      lv
      |> form("#travel-form")
      |> render_submit(%{"travel" => "icp", "row_ids" => [to_string(ctx.ann_row.id)]})

      assert render(lv) =~ "Published, so travel can&#39;t be changed."
      assert Repo.all(Trip) == []
    end
  end

  describe "elsewhere" do
    test "the activity's Travel link counts the rows not set", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
      assert lv |> element("#activity-travel-not-set") |> render() =~ "2 not set"

      Repo.insert!(%Trip{
        team_id: ctx.team.id,
        activity_id: ctx.activity.id,
        member_id: ctx.ann_row.member_id,
        d4h_attendance_id: ctx.ann_row.d4h_attendance_id,
        travel: "icp",
        km: 50
      })

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
      assert lv |> element("#activity-travel-not-set") |> render() =~ "1 not set"
    end

    test "Change activity says how many rows aren't set", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/edit")

      text = lv |> element("#activity-travel-count") |> render()
      assert text =~ "2 of 2 attendance rows"
      assert text =~ "Travel can&#39;t be changed once the activity is published."
    end

    test "an absent row has no travel", ctx do
      Repo.update_all(Attendance, set: [status: "absent"])
      lv = open(ctx)
      assert has_element?(lv, "#travel-nobody")
    end
  end
end
