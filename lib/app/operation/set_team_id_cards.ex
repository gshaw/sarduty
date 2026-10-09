defmodule App.Operation.SetTeamIdCards do
  @moduledoc """
  Lets a team issue ID cards, or stops it. Only a SAR Duty admin does this, from
  /admin/id-cards: a card verifies on SAR Duty's verify site, and anyone can sign up a
  team on SAR Duty Records, so a team is checked before it may issue them. Turning it off
  cancels every live card on the team, and phones holding one are told to fetch the
  voided pass, so turning it back on never wakes old cards.
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.PushPassUpdates
  alias App.Operation.UpdateGooglePasses
  alias App.Repo

  def call(%Team{} = team, enabled, %User{is_admin: true} = admin, now \\ DateTime.utc_now())
      when is_boolean(enabled) do
    {:ok, {team, revoked}} =
      Repo.transaction(fn ->
        team = team |> Ecto.Changeset.change(id_cards_enabled: enabled) |> Repo.update!()
        revoked = if enabled, do: [], else: MemberCard.revoke_team!(team, now)
        kind = if enabled, do: :id_cards_turned_on, else: :id_cards_turned_off

        Event.record!(kind,
          team_id: team.id,
          user_id: admin.id,
          data: %{revoked: length(revoked)}
        )

        {team, revoked}
      end)

    PushPassUpdates.push_cards(revoked)
    UpdateGooglePasses.update_cards(revoked, now)
    {:ok, team}
  end
end
