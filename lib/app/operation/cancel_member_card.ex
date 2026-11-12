defmodule App.Operation.CancelMemberCard do
  @moduledoc """
  Cancel ID card (#964, #1012): a team admin takes a member's card. It revokes it, its job
  pushes the voided Apple pass and expires the Google one
  (App.Worker.UpdateCancelledCardWorker), and the member's history says who. It makes no
  new card: Issue ID card does, for a lost phone, and Every member gets a card does at the
  next refresh for a member who can have one (App.Operation.IssueEveryMemberCard), so the
  confirm says which.

  It works on any card. A retiring member's card otherwise stays and says Not active,
  which comes back by itself; Cancel is for one who shouldn't keep it at all.
  """

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.MemberStandingChange
  alias App.Model.Team
  alias App.Repo
  alias App.Worker.UpdateCancelledCardWorker

  @doc "`{:ok, cards}`, the cards it cancelled, or `{:error, :no_card}` when they have none."
  def call(%Team{} = team, %Member{team_id: team_id} = member, %User{} = user, now)
      when team_id == team.id do
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
