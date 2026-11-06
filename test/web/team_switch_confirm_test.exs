defmodule Web.TeamSwitchConfirmTest do
  # Turning off a team's ID cards at 2, 6, and 12 (/styles/confirm-dialog#many), and its
  # Agents, from 0.
  use ExUnit.Case, async: true

  alias App.Model.Team
  alias Web.TeamSwitchConfirm

  @team %Team{name: "Coast Range SAR"}

  test "Turn off ID cards counts the ID cards, and from 10 waits on a box" do
    assert TeamSwitchConfirm.id_cards_off(@team, 2) == %{
             "data-confirm" =>
               "Turn off ID cards for Coast Range SAR? This cancels its 2 ID cards, and its team admins get an email."
           }

    six = TeamSwitchConfirm.id_cards_off(@team, 6)
    refute Map.has_key?(six, "data-confirm-check")

    assert TeamSwitchConfirm.id_cards_off(@team, 12)["data-confirm-check"] ==
             "I understand 12 ID cards stop working."
  end

  test "Turn off Agents asks nothing with none, and waits on a box from 1" do
    assert TeamSwitchConfirm.agents_off(@team, 0) == %{}

    assert TeamSwitchConfirm.agents_off(@team, 1) == %{
             "data-confirm" =>
               "Turn off Agents for Coast Range SAR? This disconnects 1 AI agent.",
             "data-confirm-check" => "I understand 1 AI agent stops working."
           }

    assert TeamSwitchConfirm.agents_off(@team, 2)["data-confirm-check"] ==
             "I understand 2 AI agents stop working."

    assert TeamSwitchConfirm.agents_off(@team, 12)["data-confirm-check"] ==
             "I understand 12 AI agents stop working."
  end
end
