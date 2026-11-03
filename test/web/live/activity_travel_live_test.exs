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
      activity_fixture(team, %{
        title: "Missing hiker",
        ref_id: "01472",
        started_at: started_at,
        finished_at: DateTime.add(started_at, 5, :hour)
      })

    ann = member_fixture(team, %{name: "Ann Smith", address: "1 Home Rd"})
    bob = member_fixture(team, %{name: "Bob Jones", address: nil})
    ann_row = attendance_fixture(activity, ann)
    bob_row = attendance_fixture(activity, bob)
    stub_mapbox(self())

    %{
      conn: log_in_user(conn, user),
      user: user,
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
      assert lv |> element(".tabs a", "Travel") |> render() =~ ~r/badge[^>]*>\s*1\s*</
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

    test "one list of how they got there, and one button that counts the checked rows",
         ctx do
      lv = open(ctx)
      assert has_element?(lv, "#travel-set-rows[disabled]", "Set rows")
      assert has_element?(lv, "#travel-choice-icp", "Drove to the ICP")
      assert has_element?(lv, "#travel-choice-clear", "Not set")

      ids = [to_string(ctx.ann_row.id), to_string(ctx.bob_row.id)]
      lv |> form("#travel-form", %{"row_ids" => ids}) |> render_change()
      assert has_element?(lv, "#travel-set-rows[disabled]", "Set 2 rows")

      lv |> form("#travel-form", %{"row_ids" => ids, "travel" => "icp"}) |> render_change()
      refute has_element?(lv, "#travel-set-rows[disabled]")

      # Other waits for its km.
      lv |> form("#travel-form", %{"row_ids" => ids, "travel" => "other"}) |> render_change()
      assert has_element?(lv, "#travel-set-rows[disabled]")

      lv
      |> form("#travel-form", %{"row_ids" => ids, "travel" => "other", "km" => "90"})
      |> render_change()

      refute has_element?(lv, "#travel-set-rows[disabled]")
    end

    test "Set comes first with its km in total, then Not set next to the choices", ctx do
      lv = open(ctx)
      set(lv, [ctx.ann_row], "icp")

      assert lv |> element("#travel-total") |> render() =~ "50 km in total"

      html = lv |> element("#travel-form") |> render()
      {set_at, _} = :binary.match(html, ~s(id="travel-set"))
      {not_set_at, _} = :binary.match(html, ~s(id="travel-not-set"))
      {how_at, _} = :binary.match(html, ~s(id="travel-how"))
      assert set_at < not_set_at and not_set_at < how_at
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

    test "Clear takes the checked rows' travel away, back to not set", ctx do
      lv = open(ctx)
      set(lv, [ctx.ann_row, ctx.bob_row], "passenger")
      ids = [to_string(ctx.ann_row.id)]
      lv |> form("#travel-form", %{"row_ids" => ids, "travel" => "clear"}) |> render_change()

      refute has_element?(lv, "#travel-set-rows[disabled]")

      set(lv, [ctx.ann_row], "clear")

      assert render(lv) =~ "1 row cleared."
      assert lv |> element("#travel-not-set") |> render() =~ "Ann Smith"
      assert [%Trip{member_id: bob_id}] = Repo.all(Trip)
      assert bob_id == ctx.bob_row.member_id
    end

    test "a published activity's travel can't change", ctx do
      ctx.activity |> Ecto.Changeset.change(is_published: true) |> Repo.update!()
      lv = open(ctx)

      assert has_element?(lv, "#travel-locked")
      refute has_element?(lv, "#travel-how")
      refute has_element?(lv, "#travel-select-#{ctx.ann_row.id}")

      lv
      |> form("#travel-form")
      |> render_submit(%{"travel" => "icp", "row_ids" => [to_string(ctx.ann_row.id)]})

      assert render(lv) =~ "Published, so travel can&#39;t be changed."
      assert Repo.all(Trip) == []
    end
  end

  describe "the team admin's own row" do
    setup ctx do
      me = Repo.get_by!(App.Model.Member, team_id: ctx.team.id, email: ctx.user.email)
      %{my_row: attendance_fixture(ctx.activity, me)}
    end

    test "Your travel's save shows in the table", ctx do
      lv = open(ctx)
      id = ctx.my_row.d4h_attendance_id

      lv |> element("#activity-your-travel-change-#{id}", "Set travel") |> render_click()

      lv
      |> form("#activity-your-travel-form", %{"travel" => "other", "km" => "12"})
      |> render_submit()

      render_async(lv)
      assert lv |> element("#travel-set #travel-row-#{ctx.my_row.id}") |> render() =~ "12 km"
    end

    test "the table's save shows in Your travel", ctx do
      lv = open(ctx)
      assert lv |> element("#activity-your-travel") |> render() =~ "Not set yet."

      set(lv, [ctx.my_row], "other", "12")

      assert lv |> element("#activity-your-travel") |> render() =~ "12 km there and back"
    end
  end

  describe "elsewhere" do
    test "Overview has the tags, map, and description; Members is its own tab", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
      assert has_element?(lv, ~s{.tabs a[aria-current="page"]}, "Overview")
      assert has_element?(lv, "#activity-map")
      refute has_element?(lv, "#members-table")

      {:ok, lv, _html} =
        live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/members")

      assert has_element?(lv, ~s{.tabs a[aria-current="page"]}, "Members")
      assert has_element?(lv, "#members-table", "Ann Smith")
      refute has_element?(lv, "#activity-map")
    end

    test "Overview has no stat boxes; Attendance in the details has the exact hours", ctx do
      Repo.insert!(%Trip{
        team_id: ctx.team.id,
        activity_id: ctx.activity.id,
        member_id: ctx.ann_row.member_id,
        d4h_attendance_id: ctx.ann_row.d4h_attendance_id,
        travel: "icp",
        km: 50
      })

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")

      refute has_element?(lv, "#activity-stats")
      refute has_element?(lv, "#chart-hours-by-member")
    end

    test "the activity's Travel tab counts the rows not set, from the finish", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
      assert lv |> element(".tabs a", "Travel") |> render() =~ "2"

      # Before the finish, members are still out: the tab is there, without a count.
      later =
        ctx.activity
        |> Ecto.Changeset.change(
          finished_at: DateTime.utc_now() |> DateTime.add(1, :hour) |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
      refute lv |> element(".tabs a", "Travel") |> render() =~ "badge"

      later |> Ecto.Changeset.change(finished_at: ctx.activity.finished_at) |> Repo.update!()

      Repo.insert!(%Trip{
        team_id: ctx.team.id,
        activity_id: ctx.activity.id,
        member_id: ctx.ann_row.member_id,
        d4h_attendance_id: ctx.ann_row.d4h_attendance_id,
        travel: "icp",
        km: 50
      })

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
      assert lv |> element(".tabs a", "Travel") |> render() =~ "1"
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

  # Members check (#230): Ann's travel is set, and Bob's isn't.
  describe "Members check" do
    setup ctx do
      team = ctx.team |> Ecto.Changeset.change(member_logins: true) |> Repo.update!()

      trip =
        Repo.insert!(%Trip{
          team_id: team.id,
          activity_id: ctx.activity.id,
          member_id: ctx.ann.id,
          d4h_attendance_id: ctx.ann_row.d4h_attendance_id,
          travel: "icp",
          km: 62,
          set_by_user_id: ctx.user.id
        })

      %{team: team, trip: trip}
    end

    test "it says who has checked, and that it's up to them", ctx do
      lv = open(ctx)
      text = lv |> element("#travel-checked") |> render()

      assert text =~ "Members can check theirs before you publish"
      assert text =~ "0 of 1 member have checked."
      refute has_element?(lv, "#travel-ask")
    end

    test "a team without member logins says its members can't check", ctx do
      ctx.team |> Ecto.Changeset.change(member_logins: false) |> Repo.update!()
      lv = open(ctx)

      assert has_element?(lv, "#travel-no-logins")
    end
  end
end
