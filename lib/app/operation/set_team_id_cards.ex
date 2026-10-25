defmodule App.Operation.SetTeamIdCards do
  @moduledoc """
  Lets a team issue ID cards, or stops it. A card verifies on SAR Duty's verify site, and
  anyone can sign up a team on SAR Duty Records, so a SAR Duty admin checks a team before
  it may issue them: when turning on its cards, or when adding it to an organization
  (#512). So a SAR Duty admin acts, from /admin/id-cards, or one of the team's own
  organization admins, from the team's page in the organization. Anyone else is
  refused, which also stops someone removed while their page is still open.

  Turning it off cancels every live card on the team, and phones holding one are told to
  fetch the voided pass, so turning it back on never wakes old cards. Either way the
  team's team admins get an email.
  """

  alias App.Accounts.User
  alias App.Mailer.TeamAdminMailer
  alias App.Model.Event
  alias App.Model.MemberCard
  alias App.Model.OrganizationAdmin
  alias App.Model.Team
  alias App.Operation.PushPassUpdates
  alias App.Operation.UpdateGooglePasses
  alias App.Repo

  def call(%Team{} = team, enabled, %User{} = user, now \\ DateTime.utc_now())
      when is_boolean(enabled) do
    if allowed?(team, user), do: set(team, enabled, user, now), else: {:error, :forbidden}
  end

  @doc "Whether the user may turn the team's ID cards on or off."
  def allowed?(_team, %User{is_admin: true}), do: true

  def allowed?(%Team{organization_id: organization_id}, %User{} = user),
    do: OrganizationAdmin.admin_of?(organization_id, user)

  defp set(team, enabled, user, now) do
    {:ok, {team, revoked}} =
      Repo.transaction(fn ->
        team = team |> Ecto.Changeset.change(id_cards_enabled: enabled) |> Repo.update!()
        revoked = if enabled, do: [], else: MemberCard.revoke_team!(team, now)
        kind = if enabled, do: :id_cards_turned_on, else: :id_cards_turned_off

        Event.record!(kind,
          team_id: team.id,
          user_id: user.id,
          data: %{revoked: length(revoked)}
        )

        {team, revoked}
      end)

    PushPassUpdates.push_cards(revoked)
    UpdateGooglePasses.update_cards(revoked, now)
    TeamAdminMailer.deliver_id_cards(team, enabled, user.email, length(revoked), now)
    {:ok, team}
  end
end
