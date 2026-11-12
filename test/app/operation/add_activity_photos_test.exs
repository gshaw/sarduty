defmodule App.Operation.AddActivityPhotosTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Adapter.FileStore
  alias App.Model.Activity
  alias App.Model.ActivityPhoto
  alias App.Operation.AddActivityPhotos

  # Adding photos to an activity (#1032): who may, and what is kept of each photo.
  @now ~U[2026-11-04 18:00:00Z]

  describe "check/3, who may add" do
    # An exercise that started an hour ago, with no logged time.
    defp activity(attrs \\ %{}) do
      struct!(
        %Activity{
          activity_kind: "exercise",
          started_at: ~U[2026-11-04 17:00:00Z],
          finished_at: ~U[2026-11-04 19:00:00Z]
        },
        attrs
      )
    end

    @member %{team_admin?: false, attended?: true}
    @absent %{team_admin?: false, attended?: false}
    @team_admin %{team_admin?: true, attended?: false}

    test "a member who attended adds, to an exercise or an event" do
      event = activity(%{activity_kind: "event"})

      assert AddActivityPhotos.check(activity(), @member, @now) == :ok
      assert AddActivityPhotos.check(event, @member, @now) == :ok
    end

    test "a member who did not attend does not" do
      assert AddActivityPhotos.check(activity(), @absent, @now) == {:error, :not_attended}
    end

    test "a team admin adds whether they attended or not" do
      assert AddActivityPhotos.check(activity(), @team_admin, @now) == :ok
    end

    test "nobody adds to an incident" do
      incident = activity(%{activity_kind: "incident"})

      for who <- [@member, @team_admin],
          do: assert(AddActivityPhotos.check(incident, who, @now) == {:error, :kind})
    end

    test "nobody adds to an activity with logged time, such as chores" do
      chores = activity(%{activity_kind: "event", logged_minutes: 90})

      for who <- [@member, @team_admin],
          do: assert(AddActivityPhotos.check(chores, who, @now) == {:error, :kind})
    end

    test "nobody adds before the activity starts" do
      coming = activity(%{started_at: ~U[2026-11-04 18:00:01Z]})

      for who <- [@member, @team_admin],
          do: assert(AddActivityPhotos.check(coming, who, @now) == {:error, :not_started})

      # From the start on.
      starting = activity(%{started_at: @now})
      assert AddActivityPhotos.check(starting, @member, @now) == :ok
    end

    test "nobody adds to a deleted activity" do
      deleted = activity(%{deleted_at: ~U[2026-11-04 17:30:00Z]})
      assert AddActivityPhotos.check(deleted, @team_admin, @now) == {:error, :deleted}
    end
  end

  describe "call/6" do
    setup do
      team = team_fixture(%{photos_enabled: true})
      member = member_fixture(team)
      activity = team |> activity_fixture() |> Activity.put_logged_minutes()
      attendance_fixture(activity, member)
      now = DateTime.utc_now()
      who = %{user: user_fixture(), member: member, team_admin?: false}
      %{team: team, member: member, activity: activity, who: who, now: now}
    end

    # A photo on disk, as the page holds an upload.
    defp photo_path(dir, name, bytes \\ nil) do
      path = Path.join(dir, name)
      File.write!(path, bytes || png_fixture(900, 600))
      path
    end

    @tag :tmp_dir
    test "keeps each photo's three files, and a row that waits", ctx do
      paths = [photo_path(ctx.tmp_dir, "a"), photo_path(ctx.tmp_dir, "b")]
      send = %{caption: "  Throw bag practice.  ", may_post: true}

      assert {:ok, %{added: 2, unread: 0, unsaved: 0}} =
               AddActivityPhotos.call(ctx.team, ctx.activity, ctx.who, paths, send, ctx.now)

      assert [first, second] = Repo.all(ActivityPhoto)
      assert first.file_token != second.file_token

      for photo <- [first, second] do
        assert photo.status == :waiting
        assert photo.team_id == ctx.team.id
        assert photo.activity_id == ctx.activity.id
        assert photo.member_id == ctx.member.id
        assert photo.added_by_user_id == ctx.who.user.id
        assert photo.caption == "Throw bag practice."
        assert photo.may_post
        assert {photo.width, photo.height} == {900, 600}

        for size <- ActivityPhoto.sizes() do
          key = ActivityPhoto.key(photo, size)
          assert String.starts_with?(key, "teams/#{ctx.team.id}/")
          assert {:ok, <<0xFF, 0xD8, 0xFF, _rest::binary>>} = FileStore.get(key)
        end
      end
    end

    @tag :tmp_dir
    test "permission to post is no unless it was given", ctx do
      paths = [photo_path(ctx.tmp_dir, "a")]

      for send <- [%{caption: nil, may_post: false}, %{caption: "", may_post: "true"}, %{}] do
        assert {:ok, %{added: 1}} =
                 AddActivityPhotos.call(ctx.team, ctx.activity, ctx.who, paths, send, ctx.now)
      end

      for photo <- Repo.all(ActivityPhoto) do
        refute photo.may_post
        assert photo.caption == nil
      end
    end

    @tag :tmp_dir
    test "keeps no location or camera data", ctx do
      paths = [photo_path(ctx.tmp_dir, "a", located_jpeg_fixture(800, 600))]

      assert {:ok, %{added: 1}} =
               AddActivityPhotos.call(ctx.team, ctx.activity, ctx.who, paths, %{}, ctx.now)

      photo = Repo.one!(ActivityPhoto)

      for {:ok, bytes} <- activity_photo_files(photo) do
        refute bytes =~ "Exif"
        refute bytes =~ "Canon"
      end

      assert length(activity_photo_files(photo)) == 3
    end

    @tag :tmp_dir
    test "a file SAR Duty cannot read is left out, and the rest are added", ctx do
      paths = [photo_path(ctx.tmp_dir, "a"), photo_path(ctx.tmp_dir, "b", "%PDF-1.7")]

      assert {:ok, %{added: 1, unread: 1, unsaved: 0} = result} =
               AddActivityPhotos.call(ctx.team, ctx.activity, ctx.who, paths, %{}, ctx.now)

      assert [_photo] = Repo.all(ActivityPhoto)

      assert AddActivityPhotos.result_text(result) ==
               {:error, "1 photo added. SAR Duty cannot read 1 photo. Select a JPEG."}
    end

    @tag :tmp_dir
    test "refuses more than 20 photos, no photo, and a caption over 300 characters", ctx do
      path = photo_path(ctx.tmp_dir, "a")
      call = &AddActivityPhotos.call(ctx.team, ctx.activity, ctx.who, &1, &2, ctx.now)

      twenty = List.duplicate(path, 20)

      assert call.([path | twenty], %{}) == {:error, :too_many}
      assert call.([], %{}) == {:error, :none}
      assert call.([path], %{caption: String.duplicate("a", 301)}) == {:error, :caption}
      assert Repo.all(ActivityPhoto) == []

      # 20, and 300 characters, are fine.
      assert {:ok, %{added: 20}} = call.(twenty, %{caption: String.duplicate("a", 300)})
    end

    @tag :tmp_dir
    test "asks who may add again: a member who did not attend adds nothing", ctx do
      absent = %{ctx.who | member: member_fixture(ctx.team)}
      paths = [photo_path(ctx.tmp_dir, "a")]

      assert AddActivityPhotos.call(ctx.team, ctx.activity, absent, paths, %{}, ctx.now) ==
               {:error, :not_attended}

      # Another team's member who attended their own activity does not count here.
      other = team_fixture(%{photos_enabled: true})
      stranger = member_fixture(other)
      attendance_fixture(activity_fixture(other), stranger)

      assert AddActivityPhotos.call(
               ctx.team,
               ctx.activity,
               %{ctx.who | member: stranger},
               paths,
               %{},
               ctx.now
             ) == {:error, :not_attended}

      assert Repo.all(ActivityPhoto) == []
    end

    @tag :tmp_dir
    test "a team with Photos off adds nothing", ctx do
      team = ctx.team |> Ecto.Changeset.change(photos_enabled: false) |> Repo.update!()
      refute AddActivityPhotos.available?(team)

      assert AddActivityPhotos.call(
               team,
               ctx.activity,
               ctx.who,
               [photo_path(ctx.tmp_dir, "a")],
               %{},
               ctx.now
             ) == {:error, :off}
    end
  end

  describe "may_add?/4" do
    test "a member who attended, a team admin, and nobody else" do
      team = team_fixture(%{photos_enabled: true})
      attended = member_fixture(team)
      absent = member_fixture(team)
      activity = team |> activity_fixture() |> Activity.put_logged_minutes()
      attendance_fixture(activity, attended)
      # Signed up for it, and marked absent: neither attended.
      attendance_fixture(activity, absent, %{status: "absent"})
      now = DateTime.utc_now()

      assert AddActivityPhotos.may_add?(
               team,
               activity,
               %{team_admin?: false, member: attended},
               now
             )

      refute AddActivityPhotos.may_add?(
               team,
               activity,
               %{team_admin?: false, member: absent},
               now
             )

      refute AddActivityPhotos.may_add?(team, activity, %{team_admin?: false, member: nil}, now)
      assert AddActivityPhotos.may_add?(team, activity, %{team_admin?: true, member: nil}, now)

      incident =
        team |> activity_fixture(%{activity_kind: "incident"}) |> Activity.put_logged_minutes()

      attendance_fixture(incident, attended)

      refute AddActivityPhotos.may_add?(
               team,
               incident,
               %{team_admin?: true, member: attended},
               now
             )

      chores = team |> chore_activity_fixture([60]) |> Activity.put_logged_minutes()
      refute AddActivityPhotos.may_add?(team, chores, %{team_admin?: true, member: nil}, now)
    end
  end

  # What Photos' Add photos lists (#1033): the same rule as may_add?/4, over the team.
  describe "addable/3" do
    setup do
      team = team_fixture(%{photos_enabled: true})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      at = fn days ->
        started_at = DateTime.add(now, days, :day)
        %{started_at: started_at, finished_at: DateTime.add(started_at, 2, :hour)}
      end

      %{
        team: team,
        now: now,
        cam: member_fixture(team),
        last_week: activity_fixture(team, Map.put(at.(-7), :activity_kind, "exercise")),
        yesterday: activity_fixture(team, Map.put(at.(-1), :activity_kind, "event")),
        coming: activity_fixture(team, at.(3)),
        incident: activity_fixture(team, Map.put(at.(-2), :activity_kind, "incident")),
        deleted: activity_fixture(team, Map.put(at.(-3), :deleted_at, now)),
        chores: chore_activity_fixture(team, [60])
      }
    end

    defp addable(ctx, who),
      do: ctx.team |> AddActivityPhotos.addable(who, ctx.now) |> Enum.map(& &1.id)

    test "a member has the exercises and events they attended, newest first", ctx do
      member = %{team_admin?: false, member: ctx.cam}
      assert addable(ctx, member) == []

      for activity <- [ctx.last_week, ctx.yesterday, ctx.incident, ctx.deleted, ctx.chores],
          do: attendance_fixture(activity, ctx.cam)

      # Signed up for one that has not started: not attended.
      attendance_fixture(ctx.coming, ctx.cam)
      # On another team's exercise, by a member there.
      other = team_fixture(%{photos_enabled: true})
      attendance_fixture(activity_fixture(other), member_fixture(other))

      assert addable(ctx, member) == [ctx.yesterday.id, ctx.last_week.id]
    end

    test "a member marked absent, and someone who is no member, have none", ctx do
      attendance_fixture(ctx.yesterday, ctx.cam, %{status: "absent"})

      assert addable(ctx, %{team_admin?: false, member: ctx.cam}) == []
      assert addable(ctx, %{team_admin?: false, member: nil}) == []
    end

    test "a team admin has every exercise and event that has started", ctx do
      assert addable(ctx, %{team_admin?: true, member: nil}) ==
               [ctx.yesterday.id, ctx.last_week.id]
    end

    test "a team with Photos off has none", ctx do
      team = ctx.team |> Ecto.Changeset.change(photos_enabled: false) |> Repo.update!()

      assert AddActivityPhotos.addable(team, %{team_admin?: true, member: nil}, ctx.now) == []
    end
  end

  describe "result_text/1" do
    test "says what was added, and that a team admin checks it" do
      assert AddActivityPhotos.result_text(%{added: 1, unread: 0, unsaved: 0}) ==
               {:info, "1 photo added. A team admin checks it."}

      assert AddActivityPhotos.result_text(%{added: 3, unread: 0, unsaved: 0}) ==
               {:info, "3 photos added. A team admin checks them."}
    end

    test "says what was left out" do
      assert AddActivityPhotos.result_text(%{added: 0, unread: 2, unsaved: 0}) ==
               {:error, "No photos added. SAR Duty cannot read 2 photos. Select JPEGs."}

      assert AddActivityPhotos.result_text(%{added: 2, unread: 0, unsaved: 1}) ==
               {:error, "2 photos added. 1 photo did not save. Add it again."}
    end
  end
end
