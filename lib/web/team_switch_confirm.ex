defmodule Web.TeamSwitchConfirm do
  @moduledoc """
  The confirm for turning off a team's ID cards, on Adminland's team page and an
  organization's: a count, and from Web.Components.Messages.check_from/0 a box naming
  it (/styles/confirm-dialog#many). Pure.
  """

  alias Service.Format
  alias Web.Components.Messages

  @doc "Turn off ID cards cancels the team's `cards`."
  def id_cards_off(team, cards) do
    cards_text = Format.count(cards, one: "%d ID card", many: "%d ID cards")

    Map.merge(
      %{
        "data-confirm" =>
          "Turn off ID cards for #{team.name}? This cancels its #{cards_text}, and its team admins get an email."
      },
      Messages.confirm_check(cards, "I understand #{cards_text} stop working.")
    )
  end
end
