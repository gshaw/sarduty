defmodule App.Operation.ReplaceMemberCard do
  @moduledoc """
  Replace ID card and Cancel ID card, one button on the ID Card tab (#1012). The member's
  card always stops working; a new one is made only for a member who can have one
  (IssueMemberCard.refusal/2): in good standing and with a photo. So the button says
  Replace ID card for a member who can, and Cancel ID card for one who is retiring,
  retired, or has no photo, and action/2 is the one place that decides which.

  Replace makes a new card with a new code and emails it (SendMemberCard). Cancel makes
  none: it revokes the card, its job pushes the voided Apple pass and expires the Google
  one (App.Worker.UpdateCancelledCardWorker), and the member's history says who (#964).
  A retiring member's card otherwise stays and says Not active, which comes back by
  itself. A member who later can have a card, by coming back or with a photo, has no live
  card, so Every member gets a card issues them one (App.Operation.IssueEveryMemberCard).
  """

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.MemberStandingChange
  alias App.Model.Team
  alias App.Operation.CheckMemberPhoto
  alias App.Operation.IssueMemberCard
  alias App.Operation.SendMemberCard
  alias App.Repo
  alias App.Worker.UpdateCancelledCardWorker

  @doc "Pure. What the button does for the member now: `:replace` or `:cancel`."
  def action(%Member{} = member, now),
    do: if(IssueMemberCard.refusal(member, now), do: :cancel, else: :replace)

  @doc """
  Does `expected`, the action the team admin confirmed. The photo is checked live first,
  for a member in good standing, so one added a minute ago counts. When that changes the
  action, nothing happens: `{:error, {:changed, action}}`, so the button can change and
  say why. Otherwise `{:ok, :replaced, card}`, `{:ok, :cancelled}`, or `{:error,
  :no_card}` or `{:error, :id_cards_off}`.
  """
  def call(%Team{} = team, %Member{team_id: team_id} = member, %User{} = user, expected, now)
      when team_id == team.id and expected in [:replace, :cancel] do
    member = check_photo(member, now)

    case action(member, now) do
      ^expected -> run(expected, team, member, user, now)
      action -> {:error, {:changed, action}}
    end
  end

  # Retiring and retired members get no card whatever the photo, so no request.
  defp check_photo(member, now) do
    if Member.good_standing?(member, now),
      do: member |> Repo.preload(:team) |> CheckMemberPhoto.call(),
      else: member
  end

  defp run(:replace, team, member, _user, now) do
    case MemberCard.find_current(team, member) do
      nil ->
        {:error, :no_card}

      _card ->
        with {:ok, card} <- SendMemberCard.issue(team, member, now), do: {:ok, :replaced, card}
    end
  end

  defp run(:cancel, team, member, user, now) do
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
        end
      end)

    with {:ok, _change} <- result do
      Phoenix.PubSub.broadcast(App.PubSub, MemberCard.pass_topic(member.id), :card_changed)
      {:ok, :cancelled}
    end
  end
end
