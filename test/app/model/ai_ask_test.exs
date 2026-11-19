defmodule App.Model.AIAskTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.AIAsk

  @now ~U[2026-11-16 20:00:00.000000Z]

  defp ask!(owner, user, kind \\ :form),
    do:
      AIAsk.record!(
        AIAsk.owner(owner) ++
          [user_id: user.id, kind: kind, model: "m", outcome: :used, asked_at: @now]
      )

  # An organization's form asks (#1089) count toward its own daily limit, apart from its
  # teams', and Adminland names each by its owner.
  test "an organization's asks count apart from its teams', and show under its name" do
    team = team_fixture(%{name: "Valley SAR"})
    organization = organization_fixture([team], %{name: "Western SAR Association"})
    user = user_fixture()

    ask!(team, user, :report)
    ask!(organization, user)
    ask!(organization, user)
    ask!(organization, user, :history_line)

    assert AIAsk.count_today(team, @now) == 1
    assert AIAsk.count_today(organization, @now) == 2

    names = @now |> AIAsk.month_summary() |> Map.fetch!(:teams) |> Enum.map(&{&1.id, &1.name})
    assert {"team-#{team.id}", "Valley SAR"} in names
    assert {"organization-#{organization.id}", "Western SAR Association"} in names

    assert [
             "Western SAR Association",
             "Western SAR Association",
             "Western SAR Association",
             "Valley SAR"
           ] ==
             10 |> AIAsk.get_recent() |> Enum.map(&AIAsk.owner_name/1)
  end
end
