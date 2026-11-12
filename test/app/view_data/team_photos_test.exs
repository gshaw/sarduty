defmodule App.ViewData.TeamPhotosTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.ActivityPhoto
  alias App.Operation.StarActivityPhoto
  alias App.ViewData.TeamPhotos

  # cspell:ignore Noor -- Noor Aziz, of the Coast Range SAR cast
  # Toronto, whose winter is always 5 hours behind UTC, so a year's edge is a known time.
  @zone "America/Toronto"

  # A photo as best_of/3 reads it: its stars, when it was added, and when its activity
  # started. Nothing here touches the database.
  defp photo(id, stars, opts \\ []) do
    %ActivityPhoto{
      id: id,
      stars: stars,
      inserted_at: Keyword.get(opts, :added, ~U[2026-06-01 12:00:00.000000Z]),
      activity: %{started_at: Keyword.get(opts, :started, ~U[2026-06-01 02:00:00Z])}
    }
  end

  defp ids(photos), do: Enum.map(photos, & &1.id)

  describe "best_of/3" do
    test "puts the most stars first, and leaves out a photo with none" do
      photos = [photo(1, 2), photo(2, 0), photo(3, 9), photo(4, 5)]

      assert photos |> TeamPhotos.best_of(2026, @zone) |> ids() == [3, 4, 1]
    end

    test "among equals, the newest photo comes first" do
      photos = [
        photo(1, 3, added: ~U[2026-03-01 12:00:00.000000Z]),
        photo(2, 3, added: ~U[2026-09-01 12:00:00.000000Z]),
        photo(3, 3, added: ~U[2026-06-01 12:00:00.000000Z]),
        # Added in the same instant as 2: the later row wins.
        photo(4, 3, added: ~U[2026-09-01 12:00:00.000000Z])
      ]

      assert photos |> TeamPhotos.best_of(2026, @zone) |> ids() == [4, 2, 3, 1]
    end

    test "stops at 24" do
      photos = for id <- 1..30, do: photo(id, id)

      best = TeamPhotos.best_of(photos, 2026, @zone)

      assert length(best) == 24
      assert ids(best) == Enum.to_list(30..7//-1)
    end

    test "takes only photos whose activity started that year, in the team's time zone" do
      photos = [
        # 23:30 on Dec 31, 2025 in Toronto.
        photo(1, 4, started: ~U[2026-01-01 04:30:00Z]),
        # 00:30 on Jan 1, 2026 in Toronto.
        photo(2, 4, started: ~U[2026-01-01 05:30:00Z]),
        # 23:30 on Dec 31, 2026 in Toronto, added the next year.
        photo(3, 4, started: ~U[2027-01-01 04:30:00Z], added: ~U[2027-01-05 12:00:00.000000Z]),
        photo(4, 4, started: ~U[2027-01-01 05:30:00Z])
      ]

      assert photos |> TeamPhotos.best_of(2025, @zone) |> ids() == [1]
      assert photos |> TeamPhotos.best_of(2026, @zone) |> ids() == [3, 2]
      assert photos |> TeamPhotos.best_of(2027, @zone) |> ids() == [4]
      assert TeamPhotos.best_of(photos, 2024, @zone) == []
    end
  end

  # What each view reads: an accepted photo is everyone's, and a waiting one shows only
  # under Yours, to who added it.
  describe "the views" do
    setup do
      team = team_fixture(%{photos_enabled: true, timezone: @zone})
      activity = activity_fixture(team, %{started_at: ~U[2026-06-01 02:00:00Z]})
      cam = member_fixture(team)
      noor = member_fixture(team)

      %{
        team: team,
        activity: activity,
        cam: cam,
        noor: noor,
        user: user_fixture(),
        accepted: activity_photo_fixture(activity, %{member_id: cam.id, status: :accepted}),
        waiting: activity_photo_fixture(activity, %{member_id: cam.id})
      }
    end

    test "Activities lists every accepted photo, newest first, and never a waiting one", ctx do
      newer =
        activity_photo_fixture(ctx.activity, %{
          member_id: ctx.noor.id,
          status: :accepted,
          inserted_at: DateTime.add(DateTime.utc_now(), 1, :hour)
        })

      page = TeamPhotos.activities(ctx.team, ctx.user, 1)

      assert ids(page.entries) == [newer.id, ctx.accepted.id]
      assert hd(page.entries).activity.id == ctx.activity.id
    end

    test "no view shows another team's photo, a deleted activity's, or an incident's", ctx do
      other = team_fixture(%{photos_enabled: true})
      activity_photo_fixture(activity_fixture(other), %{status: :accepted})
      gone = activity_fixture(ctx.team, %{deleted_at: ~U[2026-07-01 00:00:00Z]})
      activity_photo_fixture(gone, %{status: :accepted})
      incident = activity_fixture(ctx.team, %{activity_kind: "incident"})
      hidden = activity_photo_fixture(incident, %{member_id: ctx.cam.id, status: :accepted})
      {:ok, true} = StarActivityPhoto.call(hidden, ctx.user)

      who = %{member: ctx.cam, user: ctx.user}

      assert ids(TeamPhotos.activities(ctx.team, ctx.user, 1).entries) == [ctx.accepted.id]
      assert TeamPhotos.starred(ctx.team, ctx.user, 1).entries == []
      refute hidden.id in ids(TeamPhotos.added(ctx.team, who, ctx.user, 1).entries)
      assert TeamPhotos.counts(ctx.team, ctx.user, who) == %{activities: 1, stars: 0, yours: 2}
    end

    test "Yours has what the person added, waiting ones too, and nobody else's", ctx do
      theirs = activity_photo_fixture(ctx.activity, %{member_id: ctx.noor.id})
      cam = %{member: ctx.cam, user: ctx.user}
      noor = %{member: ctx.noor, user: ctx.user}

      assert ctx.team |> TeamPhotos.added(cam, ctx.user, 1) |> Map.fetch!(:entries) |> ids() ==
               [ctx.waiting.id, ctx.accepted.id]

      assert ids(TeamPhotos.added(ctx.team, noor, ctx.user, 1).entries) == [theirs.id]
    end

    test "a team admin with no member row has the photos their login added", ctx do
      admin = user_fixture()
      own = activity_photo_fixture(ctx.activity, %{added_by_user_id: admin.id})
      who = %{member: nil, user: admin}

      assert ids(TeamPhotos.added(ctx.team, who, admin, 1).entries) == [own.id]
    end

    test "Your stars and each photo's count follow the person looking", ctx do
      other = user_fixture()
      {:ok, true} = StarActivityPhoto.call(ctx.accepted, ctx.user)
      {:ok, true} = StarActivityPhoto.call(ctx.accepted, other)

      assert [%{stars: 2, starred: true}] = TeamPhotos.starred(ctx.team, ctx.user, 1).entries
      assert [%{stars: 2, starred: true}] = TeamPhotos.best(ctx.team, other, 2026)

      nobody = user_fixture()
      assert TeamPhotos.starred(ctx.team, nobody, 1).entries == []
      assert [%{stars: 2, starred: false}] = TeamPhotos.best(ctx.team, nobody, 2026)
      assert TeamPhotos.best(ctx.team, nobody, 2025) == []
    end

    test "years run from the first activity with an accepted photo to this year", ctx do
      assert TeamPhotos.years(ctx.team, ~U[2026-11-12 20:00:00Z]) == [2026]

      old = activity_fixture(ctx.team, %{started_at: ~U[2024-03-01 02:00:00Z]})
      activity_photo_fixture(old, %{status: :accepted})
      # A waiting photo opens no year.
      older = activity_fixture(ctx.team, %{started_at: ~U[2022-03-01 02:00:00Z]})
      activity_photo_fixture(older)

      assert TeamPhotos.years(ctx.team, ~U[2026-11-12 20:00:00Z]) == [2026, 2025, 2024]
      assert TeamPhotos.any?(ctx.team)
    end

    test "a team with no accepted photo has this year alone", ctx do
      team = team_fixture(%{photos_enabled: true})
      activity_photo_fixture(activity_fixture(team))

      refute TeamPhotos.any?(team)
      assert TeamPhotos.years(team, ~U[2026-11-12 20:00:00Z]) == [2026]
      assert ctx.team.id != team.id
    end
  end
end
