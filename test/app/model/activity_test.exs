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
end
