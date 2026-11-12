defmodule App.Operation.FeatureActivityPhotoTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.ActivityPhoto
  alias App.Operation.FeatureActivityPhoto

  @now ~U[2026-11-12 20:00:00.000000Z]

  # Featured photos (#1033): an activity's Overview shows up to 2.
  describe "check/2" do
    test "an accepted photo is featured while the activity has room" do
      photo = %ActivityPhoto{status: :accepted}

      assert FeatureActivityPhoto.check(photo, 0) == :ok
      assert FeatureActivityPhoto.check(photo, 1) == :ok
      assert FeatureActivityPhoto.check(photo, 2) == {:error, :full}
    end

    test "one that is featured already stays so, even on a full activity" do
      photo = %ActivityPhoto{status: :accepted, featured_at: @now}

      assert FeatureActivityPhoto.check(photo, 2) == :ok
    end

    test "a waiting photo is never featured" do
      assert FeatureActivityPhoto.check(%ActivityPhoto{status: :waiting}, 0) ==
               {:error, :waiting}
    end
  end

  describe "call/3" do
    setup do
      team = team_fixture(%{photos_enabled: true})
      activity = activity_fixture(team)
      photos = for _ <- 1..3, do: activity_photo_fixture(activity, %{status: :accepted})
      %{team: team, activity: activity, photos: photos}
    end

    defp featured(activity), do: activity |> ActivityPhoto.featured() |> Enum.map(& &1.id)

    test "features 2, the first featured first, and refuses a third", ctx do
      [first, second, third] = ctx.photos

      assert {:ok, %{featured_at: @now}} = FeatureActivityPhoto.call(second, true, @now)
      later = DateTime.add(@now, 1, :minute)
      assert {:ok, _photo} = FeatureActivityPhoto.call(first, true, later)

      assert FeatureActivityPhoto.call(third, true, later) == {:error, :full}
      assert featured(ctx.activity) == [second.id, first.id]

      assert FeatureActivityPhoto.error_text(:full) ==
               "2 photos are featured already. Stop featuring one first."
    end

    test "stopping one makes room for another", ctx do
      [first, second, third] = ctx.photos
      for photo <- [first, second], do: {:ok, _} = FeatureActivityPhoto.call(photo, true, @now)

      assert {:ok, %{featured_at: nil}} = FeatureActivityPhoto.call(first, false, @now)
      assert {:ok, _photo} = FeatureActivityPhoto.call(third, true, @now)
      assert Enum.sort(featured(ctx.activity)) == Enum.sort([second.id, third.id])
    end

    test "another activity's featured photos take none of its room", ctx do
      elsewhere = activity_fixture(ctx.team)

      for _ <- 1..2 do
        photo = activity_photo_fixture(elsewhere, %{status: :accepted})
        {:ok, _photo} = FeatureActivityPhoto.call(photo, true, @now)
      end

      assert {:ok, _photo} = FeatureActivityPhoto.call(hd(ctx.photos), true, @now)
    end

    test "a waiting photo is refused, and nothing changes", ctx do
      waiting = activity_photo_fixture(ctx.activity)

      assert FeatureActivityPhoto.call(waiting, true, @now) == {:error, :waiting}
      assert featured(ctx.activity) == []
    end

    test "featuring one twice keeps when it was first featured", ctx do
      photo = hd(ctx.photos)
      {:ok, _photo} = FeatureActivityPhoto.call(photo, true, @now)
      {:ok, again} = FeatureActivityPhoto.call(photo, true, DateTime.add(@now, 1, :hour))

      assert again.featured_at == @now
    end
  end
end
