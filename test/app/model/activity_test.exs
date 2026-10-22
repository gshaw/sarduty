defmodule App.Model.ActivityTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Activity
  alias App.Model.Organization
  alias App.Model.Team

  @defaults %{primary: "Primary Hours", secondary: "Secondary Hours", other: nil}

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

  describe "visible_to_member/3" do
    defp hours_ago(hours),
      do: DateTime.utc_now() |> DateTime.add(-hours, :hour) |> DateTime.truncate(:second)

    test "every exercise and event, and only the incidents the member attended, never deleted" do
      team = team_fixture()
      member = member_fixture(team)
      now = DateTime.utc_now()

      exercise = activity_fixture(team, %{activity_kind: "exercise"})
      event = activity_fixture(team, %{activity_kind: "event"})
      attended = activity_fixture(team, %{activity_kind: "incident", started_at: hours_ago(5)})
      attendance_fixture(attended, member, %{started_at: hours_ago(5)})

      not_attended =
        activity_fixture(team, %{activity_kind: "incident", started_at: hours_ago(5)})

      attendance_fixture(not_attended, member_fixture(team), %{started_at: hours_ago(5)})
      activity_fixture(team, %{activity_kind: "exercise", deleted_at: hours_ago(1)})
      activity_fixture(team_fixture(), %{activity_kind: "exercise"})

      ids =
        Activity
        |> Activity.visible_to_member(member, now)
        |> select([a], a.id)
        |> Repo.all()
        |> Enum.sort()

      assert ids == Enum.sort([exercise.id, event.id, attended.id])

      assert_raise Ecto.NoResultsError, fn ->
        Activity.find_visible!(member, not_attended.id, now)
      end
    end
  end

  # What a member sees of the team's activities lives in Activity.visible_to_member/3
  # (#406). Every page or download members reach that shows the team's activities starts
  # there, so an incident they did not attend never shows by its title.
  test "every team page members reach goes through visible_to_member" do
    pages =
      for path <- Path.wildcard("lib/web/**/*.ex"),
          source = File.read!(path),
          source =~ "access: :team" or source =~ "pipe_through :require_team_access",
          source =~ ~r/\b(Activity|activities)\b/,
          not String.ends_with?(path, "router.ex"),
          do: {path, source}

    assert length(pages) >= 3

    for {path, source} <- pages do
      assert source =~ ~r/visible_to_member|find_visible!|visible_to:/,
             "#{path} shows members activities without Activity.visible_to_member/3"
    end

    calendar = File.read!("lib/web/controllers/activity_calendar_controller.ex")
    assert calendar =~ "find_visible!"
  end
end
