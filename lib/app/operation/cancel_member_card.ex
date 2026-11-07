defmodule App.Operation.CancelMemberCard do
  @moduledoc """
  Cancel ID card (#964): a team admin takes the card of a retiring or retired member who
  shouldn't keep one at all. It does what Replace does to the old card, with no new one:
  revokes it, and its job pushes the voided Apple pass and expires the Google one
  (App.Worker.UpdateCancelledCardWorker). The member's history says who.

  Not active stays the default for everyone else (#893): it says the true thing and comes
  back by itself. An active member's card can only be replaced, so this never becomes a
  casual way to take someone's card. A member who comes back has no live card, so Every
  member gets a card issues them a new one, as for anyone else
  (App.Operation.IssueEveryMemberCard).
  """

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.MemberStandingChange
  alias App.Model.Team
  alias App.Repo
  alias App.Worker.UpdateCancelledCardWorker

  @doc """
  `{:ok, cards}`, the cards it cancelled; `{:error, :active}` for a member in good
  standing, or `{:error, :no_card}` when they have none.
  """
  def call(%Team{} = team, %Member{team_id: team_id} = member, %User{} = user, now)
      when team_id == team.id do
    if Member.good_standing?(member, now),
      do: {:error, :active},
      else: cancel(team, member, user, now)
  end

  defp cancel(team, member, user, now) do
    result =
      Repo.transaction(fn ->
        case MemberCard.revoke_all!(team, member, now) do
          [] ->
            Repo.rollback(:no_card)

          cards ->
            UpdateCancelledCardWorker.enqueue_all(cards)

            MemberStandingChange.insert!(%MemberStandingChange{
              team_id: team.id,
              member_id: member.id,
              user_id: user.id,
              action: :card_cancelled
            })

            cards
        end
      end)

    with {:ok, _cards} <- result do
      Phoenix.PubSub.broadcast(App.PubSub, MemberCard.pass_topic(member.id), :card_changed)
      result
    end
  end
end
