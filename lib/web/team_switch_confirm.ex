defmodule Web.TeamSwitchConfirm do
  @moduledoc """
  The confirms for turning off a team's ID cards, on Adminland's team page and an
  organization's, and its Agents, on Adminland's. ID cards: a count, and from
  Web.Components.Messages.check_from/0 a box naming it (/styles/confirm-dialog#many).
  Agents: a box from 1, since each one has to be connected again. Pure.
  """

  alias Service.Format
  alias Web.Components.Messages

  @doc "Turn off ID cards cancels the team's `cards`."
  def id_cards_off(team, cards) do
    cards_text = Format.count(cards, one: "%d card", many: "%d cards")

    Map.merge(
      %{
        "data-confirm" =>
          "Turn off ID cards for #{team.name}? This cancels its #{cards_text}, and its team admins get an email."
      },
      Messages.confirm_check(cards, "I understand #{cards_text} stop working.")
    )
  end

  @doc "Turn off Agents disconnects the team's `agents`: nothing to ask with none."
  def agents_off(_team, 0), do: %{}

  def agents_off(team, agents) do
    agents_text = Format.count(agents, one: "%d agent", many: "%d agents")
    stop = Format.count(agents, one: "%d agent stops", many: "%d agents stop")

    %{
      "data-confirm" => "Turn off Agents for #{team.name}? This disconnects #{agents_text}.",
      "data-confirm-check" => "I understand #{stop} working."
    }
  end
end
