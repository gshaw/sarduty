defmodule Web.PhotoCollectionViewsTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Operation.StarActivityPhoto

  # cspell:ignore Noor -- Noor Aziz, of the Coast Range SAR cast
  # Photos' views of the team's activity photos (#1033): Best of a year, Activities,
  # Your stars, and Yours, for everyone, before a team admin's Members, No photo, and
  # Waiting. Web.PhotoCollectionLiveTest has the members' photos.
  setup %{conn: conn} do
    # Best of opens on this year, so the page's year is set here.
    App.Clock.freeze(~U[2026-11-12 20:00:00Z])
    team = member_logins_team_fixture(%{name: "Coast Range SAR", photos_enabled: true})
    admin = user_fixture()
    manager_fixture(team, %{email: admin.email, name: "Alex Chen"})
    cam = member_fixture(team, %{name: "Cameron Ruiz", d4h_permission: 2})
    noor = member_fixture(team, %{name: "Noor Aziz", d4h_permission: 2})

    activity =
      activity_fixture(team, %{
        title: "Swiftwater training",
        started_at: ~U[2026-11-10 02:00:00Z],
        finished_at: ~U[2026-11-10 04:00:00Z]
      })

    attendance_fixture(activity, cam)

    %{conn: conn, team: team, admin: admin, cam: cam, noor: noor, activity: activity, year: 2026}
  end

  # Logged in as the member: their email is their login.
  defp as(conn, %{email: email}), do: log_in_user(conn, user(%{email: email}))
  defp user(%{email: email}), do: App.Accounts.get_user_by_email(email) || user_fixture(%{email: email})

  defp accepted(ctx, attrs \\ %{}),
    do:
      activity_photo_fixture(
        ctx.activity,
        Map.merge(%{member_id: ctx.cam.id, status: :accepted}, attrs)
      )

  defp ids(lv, grid) do
    lv
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("#{grid} > li")
    |> Enum.flat_map(&Floki.attribute(&1, "id"))
  end

  defp views(lv) do
    lv
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("#photos-switch > a")
    |> Enum.flat_map(&Floki.attribute(&1, "id"))
  end

  describe "the view Photos opens on" do
    test "a member with no accepted photo on the team gets Yours", ctx do
      # A waiting photo is not the team's yet.
      activity_photo_fixture(ctx.activity, %{member_id: ctx.noor.id})

      {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(~p"/teams/#{ctx.team}/photos")

      assert has_element?(lv, "#photos-view-yours[aria-current=page]", "Yours")
      assert has_element?(lv, "#your-photo h2", "Your photo")

      assert views(lv) ==
               ~w(photos-view-best photos-view-activities photos-view-stars photos-view-yours)
    end

    test "a team admin with no accepted photo on the team gets Members", ctx do
      {:ok, lv, _html} = ctx.conn |> log_in_user(ctx.admin) |> live(~p"/teams/#{ctx.team}/photos")

      assert has_element?(lv, "#photos-view-members[aria-current=page]", "Members")
      assert has_element?(lv, "#photos")

      assert views(lv) ==
               ~w(photos-view-best photos-view-activities photos-view-stars photos-view-yours
                  photos-view-members photos-view-no-photo photos-view-waiting)
    end

    test "once the team has an accepted photo, both get Best of this year", ctx do
      accepted(ctx)

      for conn <- [as(ctx.conn, ctx.cam), log_in_user(ctx.conn, ctx.admin)] do
        {:ok, lv, _html} = live(conn, ~p"/teams/#{ctx.team}/photos")

        assert has_element?(lv, "#photos-view-best[aria-current=page]", "Best of #{ctx.year}")
        assert has_element?(lv, "#side-nav-photos[aria-current=page]")
      end
    end

    test "a view the URL names opens, and one that is not theirs is not found", ctx do
      accepted(ctx)
      conn = as(ctx.conn, ctx.cam)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{ctx.team}/photos?view=yours")
      assert has_element?(lv, "#photos-view-yours[aria-current=page]")

      for view <- ~w(members no-photo waiting asked) do
        assert_raise Web.Status.NotFound, fn ->
          live(conn, ~p"/teams/#{ctx.team}/photos?#{[view: view]}")
        end
      end
    end
  end

  describe "Best of the year" do
    test "lists the starred photos, the most stars first, each naming its activity", ctx do
      top = accepted(ctx, %{caption: "Throw bag practice at Cedar Creek."})
      next = accepted(ctx)
      unstarred = accepted(ctx)
      {:ok, true} = StarActivityPhoto.call(top, ctx.admin)
      {:ok, true} = StarActivityPhoto.call(top, user(ctx.cam))
      {:ok, true} = StarActivityPhoto.call(next, ctx.admin)

      {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(~p"/teams/#{ctx.team}/photos")

      assert has_element?(lv, "#photos-view-best", "2")

      assert has_element?(
               lv,
               "#photos-best-hint",
               "The 24 photos with the most stars from #{ctx.year}, most first."
             )

      assert ids(lv, "#photos-best") == ["photo-#{top.id}", "photo-#{next.id}"]
      refute has_element?(lv, "#photo-#{unstarred.id}")

      # A tile is the photo, which opens its page, its stars, and its activity's name.
      page = ~p"/teams/#{ctx.team}/photos/#{top.id}"

      assert has_element?(
               lv,
               ~s|#photo-#{top.id}-tile a[href="#{page}"] img[alt="Throw bag practice at Cedar Creek."]|
             )

      assert has_element?(lv, "#photo-#{top.id}-tile-stars.is-starred", "2")
      assert has_element?(lv, "#photo-#{next.id}-tile-stars:not(.is-starred)", "1")
      tab = ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/photos"
      assert has_element?(lv, ~s|#photo-#{top.id}-activity[href="#{tab}"]|, "Swiftwater training")
    end

    test "with no stars it says how to give one", ctx do
      accepted(ctx)

      {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(~p"/teams/#{ctx.team}/photos")

      assert has_element?(lv, "#photos-view-best", "0")

      assert has_element?(
               lv,
               "#photos-best-empty",
               "No stars yet for #{ctx.year}. Open a photo and star it."
             )

      refute has_element?(lv, "#photos-best")
    end

    test "Year picks another year's, and a year with no photos is not found", ctx do
      old = activity_fixture(ctx.team, %{title: "Rope rescue", started_at: ~U[2024-05-05 02:00:00Z]})
      older = activity_photo_fixture(old, %{member_id: ctx.cam.id, status: :accepted})
      {:ok, true} = StarActivityPhoto.call(older, ctx.admin)
      this_year = accepted(ctx)
      {:ok, true} = StarActivityPhoto.call(this_year, ctx.admin)

      {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(~p"/teams/#{ctx.team}/photos")

      assert ids(lv, "#photos-best") == ["photo-#{this_year.id}"]
      assert has_element?(lv, ~s|#year option[selected][value="#{ctx.year}"]|)
      assert has_element?(lv, ~s|#year option[value="2024"]|)

      lv |> form("#years") |> render_change(%{"year" => "2024"})
      assert_patch(lv, ~p"/teams/#{ctx.team}/photos?view=best&year=2024")

      assert has_element?(lv, "#photos-view-best[aria-current=page]", "Best of 2024")
      assert has_element?(lv, "#photos-best-hint", "from 2024")
      assert ids(lv, "#photos-best") == ["photo-#{older.id}"]

      assert_raise Web.Status.NotFound, fn ->
        ctx.conn |> as(ctx.cam) |> live(~p"/teams/#{ctx.team}/photos?view=best&year=2019")
      end
    end
  end

  describe "Activities, Your stars, and Yours" do
    test "a member sees every accepted photo, and never another member's waiting one", ctx do
      old = accepted(ctx, %{inserted_at: ~U[2026-11-01 20:00:00.000000Z]})
      new = accepted(ctx, %{member_id: ctx.noor.id, inserted_at: ~U[2026-11-03 20:00:00.000000Z]})
      hers = activity_photo_fixture(ctx.activity, %{member_id: ctx.noor.id})
      own = activity_photo_fixture(ctx.activity, %{member_id: ctx.cam.id})
      conn = as(ctx.conn, ctx.cam)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{ctx.team}/photos?view=activities")

      assert has_element?(lv, "#photos-view-activities[aria-current=page]", "2")
      # Newest first.
      assert ids(lv, "#photos-list") == ["photo-#{new.id}", "photo-#{old.id}"]
      refute has_element?(lv, "#photo-#{own.id}")

      # Another member's waiting photo is on no view, by tile or by file.
      for view <- ~w(best activities stars yours) do
        {:ok, lv, html} = live(conn, ~p"/teams/#{ctx.team}/photos?#{[view: view]}")
        refute has_element?(lv, "#photo-#{hers.id}")
        refute html =~ "/photos/#{hers.id}/file"
      end
    end

    test "Your stars has what you starred, and says so when there are none", ctx do
      mine = accepted(ctx)
      theirs = accepted(ctx)
      {:ok, true} = StarActivityPhoto.call(theirs, ctx.admin)
      conn = as(ctx.conn, ctx.cam)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{ctx.team}/photos?view=stars")
      assert has_element?(lv, "#photos-view-stars[aria-current=page]", "0")
      assert has_element?(lv, "#photos-empty", "You have not starred a photo yet.")

      {:ok, true} = StarActivityPhoto.call(mine, user(ctx.cam))

      {:ok, lv, _html} = live(conn, ~p"/teams/#{ctx.team}/photos?view=stars")
      assert has_element?(lv, "#photos-view-stars", "1")
      assert ids(lv, "#photos-list") == ["photo-#{mine.id}"]
      refute has_element?(lv, "#photo-#{theirs.id}")
    end

    test "Yours has your member photo, then the photos you added, waiting ones marked", ctx do
      mine = accepted(ctx)
      waiting = activity_photo_fixture(ctx.activity, %{member_id: ctx.cam.id})
      accepted(ctx, %{member_id: ctx.noor.id})

      {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(~p"/teams/#{ctx.team}/photos?view=yours")

      assert has_element?(lv, "#photos-view-yours[aria-current=page]", "2")
      assert has_element?(lv, "#your-photo h2", "Your photo")
      assert has_element?(lv, "#your-photo-add[href='/teams/#{ctx.team.subdomain}/photos/members/new']")
      assert has_element?(lv, "#photos-added h2", "Photos you added")
      assert Enum.sort(ids(lv, "#photos-list")) == Enum.sort(["photo-#{mine.id}", "photo-#{waiting.id}"])
      assert has_element?(lv, "#photo-#{waiting.id}-waiting", "Waiting")
      refute has_element?(lv, "#photo-#{mine.id}-waiting")
      # A waiting photo has no page and no stars yet.
      refute has_element?(lv, "#photo-#{waiting.id}-tile-stars")
      assert has_element?(lv, "#photo-#{waiting.id}-tile a[target=_blank]")
    end

    test "a team admin's Yours has their own photo, with a link that names them", ctx do
      alex = App.Model.Member.find_by_email(ctx.team, ctx.admin.email, DateTime.utc_now())
      own = activity_photo_fixture(ctx.activity, %{member_id: alex.id})

      {:ok, lv, _html} =
        ctx.conn |> log_in_user(ctx.admin) |> live(~p"/teams/#{ctx.team}/photos?view=yours")

      add = ~p"/teams/#{ctx.team}/photos/members/new?#{[member: alex.id]}"
      assert has_element?(lv, ~s|#your-photo-add[href="#{add}"]|)
      assert has_element?(lv, "#photo-#{own.id}-waiting", "Waiting")
    end
  end

  describe "the heading's buttons" do
    test "Add photos shows for whoever may add to some activity, on the photo views", ctx do
      accepted(ctx)
      add = ~p"/teams/#{ctx.team}/photos/new"

      {:ok, lv, _html} = ctx.conn |> as(ctx.cam) |> live(~p"/teams/#{ctx.team}/photos")
      assert has_element?(lv, ~s|#photos-add[href="#{add}"]|, "Add photos")
      refute has_element?(lv, "#photo-add")
      refute has_element?(lv, "#photo-ask")

      # Noor attended nothing.
      {:ok, lv, _html} = ctx.conn |> as(ctx.noor) |> live(~p"/teams/#{ctx.team}/photos")
      refute has_element?(lv, "#photos-add")
    end

    test "a team admin's views of members' photos keep Ask for photos and Add a photo", ctx do
      accepted(ctx)
      conn = log_in_user(ctx.conn, ctx.admin)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{ctx.team}/photos")
      assert has_element?(lv, "#photos-add", "Add photos")
      refute has_element?(lv, "#photo-add")

      lv |> element("#photos-view-members") |> render_click()
      assert_patch(lv, ~p"/teams/#{ctx.team}/photos?view=members")

      assert has_element?(lv, "#photo-add", "Add a photo")
      assert has_element?(lv, "#photo-ask", "Ask for photos")
      refute has_element?(lv, "#photos-add")
      assert has_element?(lv, "#photos-members-hint", "Every current member's photo")
    end
  end
end
