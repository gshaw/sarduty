defmodule App.Model.ActivityTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Activity
  alias App.Model.Organization
  alias App.Model.Team

  @defaults %{primary: "Primary Hours", secondary: "Secondary Hours", other: nil}

  # 19:00–21:00 UTC.
  @evening %Activity{started_at: ~U[2026-10-10 19:00:00Z], finished_at: ~U[2026-10-10 21:00:00Z]}

  describe "open?/2" do
    test "an activity is open until it starts" do
      assert Activity.open?(@evening, ~U[2026-10-10 18:59:59Z])
      refute Activity.open?(@evening, ~U[2026-10-10 19:00:00Z])
      assert Activity.started?(@evening, ~U[2026-10-10 19:00:00Z])
    end

    test "a deleted activity is never open" do
      deleted = %{@evening | deleted_at: ~U[2026-10-01 12:00:00Z]}
      refute Activity.open?(deleted, ~U[2026-10-05 12:00:00Z])
    end
  end

  describe "take_attendance?/3" do
    test "a member takes attendance from 2 hours before the start to 2 hours after the end" do
      refute Activity.take_attendance?(@evening, false, ~U[2026-10-10 16:59:59Z])
      assert Activity.take_attendance?(@evening, false, ~U[2026-10-10 17:00:00Z])
      assert Activity.take_attendance?(@evening, false, ~U[2026-10-10 20:00:00Z])
      assert Activity.take_attendance?(@evening, false, ~U[2026-10-10 23:00:00Z])
      refute Activity.take_attendance?(@evening, false, ~U[2026-10-10 23:00:01Z])
    end

    test "a team admin takes attendance at any time" do
      assert Activity.take_attendance?(@evening, true, ~U[2026-10-01 12:00:00Z])
      assert Activity.take_attendance?(@evening, true, ~U[2026-10-11 09:00:00Z])
    end

    test "nobody takes attendance for a deleted activity" do
      deleted = %{@evening | deleted_at: ~U[2026-10-10 18:00:00Z]}
      refute Activity.take_attendance?(deleted, true, ~U[2026-10-10 20:00:00Z])
      refute Activity.take_attendance?(deleted, false, ~U[2026-10-10 20:00:00Z])
    end
  end

  describe "hours_tags/1" do
    test "a team with no organization keeps the default tags" do
      assert Activity.hours_tags(%Team{organization_id: nil}) == @defaults
    end

    test "a blank tag falls back to the default" do
      organization = %Organization{primary_hours_tag: "SRVTC Primary Activity"}

      assert Activity.hours_tags(%Team{organization: organization}) == %{
               primary: "SRVTC Primary Activity",
               secondary: "Secondary Hours",
               other: nil
             }
    end

    test "reads the organization's tags when it isn't preloaded" do
      team = team_fixture()

      organization_fixture([team], %{
        primary_hours_tag: "SRVTC Primary Activity",
        secondary_hours_tag: "SRVTC Secondary Activity"
      })

      assert team.id |> Team.get!() |> Activity.hours_tags() == %{
               primary: "SRVTC Primary Activity",
               secondary: "SRVTC Secondary Activity",
               other: nil
             }
    end

    test "a team names the tags its organization leaves blank" do
      organization = %Organization{primary_hours_tag: "SRVTC Primary Activity"}

      team = %Team{
        organization: organization,
        primary_hours_tag: "Team Primary",
        secondary_hours_tag: "Training Hrs",
        other_hours_tag: "No Hours"
      }

      assert Activity.hours_tags(team) == %{
               primary: "SRVTC Primary Activity",
               secondary: "Training Hrs",
               other: "No Hours"
             }
    end
  end

  test "tags are stored sorted, so another order is no change (#358)" do
    activity = activity_fixture(team_fixture(), %{tags: ["Rope", "Primary Hours"]})
    assert activity.tags == ["Primary Hours", "Rope"]

    assert Activity.build_changeset(activity, %{tags: ["Rope", "Primary Hours"]}).changes == %{}

    assert Activity.update!(activity, %{tags: ["Rope", "Primary Hours"]}).updated_at ==
             activity.updated_at
  end

  test "hours_tagged?/2 is true for any hours tag, the other one too" do
    tags = %{@defaults | other: "Social"}
    assert Activity.hours_tagged?(["Social"], tags)
    assert Activity.hours_tagged?(["Secondary Hours"], tags)
    refute Activity.hours_tagged?(["Training"], tags)
    refute Activity.hours_tagged?(nil, @defaults)
  end

  test "counts_as/2 picks primary over secondary, and nil for neither" do
    assert Activity.counts_as(["Secondary Hours", "Primary Hours"], @defaults) == :primary
    assert Activity.counts_as(["Secondary Hours"], @defaults) == :secondary
    assert Activity.counts_as(["Training"], @defaults) == nil
    assert Activity.counts_as(nil, @defaults) == nil
  end

  test "only Activity says whether an activity has started" do
    copies =
      for path <- Path.wildcard("lib/**/*.{ex,exs,heex}"),
          path != "lib/app/model/activity.ex",
          File.read!(path) =~
            ~r/DateTime\.before\?\(now, [\w.]*started_at\)|DateTime\.after\?\([\w.]*started_at, now\)/,
          do: path

    assert copies == [],
           "Use Activity.started?/2 or open?/2, not a started_at comparison, in: #{inspect(copies)}"
  end

  describe "missing_required_fields/1 (#681)" do
    test "finds activities with a required field of their kind left empty" do
      team = team_fixture()
      custom_field_fixture(team, %{d4h_custom_field_id: 1, required: true})
      custom_field_fixture(team, %{d4h_custom_field_id: 2})

      custom_field_fixture(team, %{
        d4h_custom_field_id: 3,
        required: true,
        archived_at: ~U[2026-01-01 00:00:00Z]
      })

      custom_field_fixture(team, %{d4h_custom_field_id: 4, target: "event", required: true})

      missing = activity_fixture(team, %{activity_kind: "incident", custom_values: %{"2" => "x"}})
      filled = activity_fixture(team, %{activity_kind: "incident", custom_values: %{"1" => [5]}})
      _not_copied = activity_fixture(team, %{activity_kind: "incident"})
      _exercise = activity_fixture(team, %{activity_kind: "exercise", custom_values: %{}})

      # D4H let a published one through, so nothing is missing that stops it.
      _published =
        activity_fixture(team, %{
          activity_kind: "incident",
          is_published: true,
          custom_values: %{}
        })

      _other_team =
        activity_fixture(team_fixture(), %{activity_kind: "incident", custom_values: %{}})

      ids = Activity |> Activity.missing_required_fields() |> Repo.all() |> Enum.map(& &1.id)

      assert ids == [missing.id]
      refute filled.id in ids
    end
  end
end
