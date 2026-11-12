defmodule App.Operation.RefreshMemberCard do
  @moduledoc """
  Refresh ID card (#1012): puts a fixed photo, name, or standing on the member's phones
  now, rather than with the monthly expiry update. Checks the photo, marks the Apple pass
  changed and tells every phone holding it to download it again, and sends Google the
  pass again with a new photo URL (BuildGooglePass), so Google fetches the photo too.
  Queues the team's sync, so a fix just made in the team's records reaches the card in
  the same minute. Same code, no email.
  """

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.CheckMemberPhoto
  alias App.Operation.PushPassUpdates
  alias App.Operation.UpdateGooglePasses
  alias App.Repo
  alias App.Worker.SyncTeamChangesWorker

  @doc "Checks the photo, then `resend/3`. `{:ok, card}` or `{:error, :no_card}`."
  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    member |> Repo.preload(:team) |> CheckMemberPhoto.call()
    resend(team, member, now)
  end

  @doc """
  Sends the card to the phones again without checking the photo, for SetMemberPhoto,
  which just set or removed it. `{:ok, card}` or `{:error, :no_card}`.
  """
  def resend(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    case MemberCard.find_current(team, member) do
      nil ->
        {:error, :no_card}

      card ->
        card = MemberCard.touch_pass_updated!(card, now)
        PushPassUpdates.push_cards([card])
        UpdateGooglePasses.update_cards([card], now)
        if SyncTeamChangesWorker.syncs?(team), do: SyncTeamChangesWorker.enqueue(team)
        {:ok, card}
    end
  end
end
