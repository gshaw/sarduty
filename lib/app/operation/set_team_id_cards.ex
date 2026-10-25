defmodule App.Operation.SetTeamIdCards do
  @moduledoc """
  Lets a team issue ID cards, or stops it. A card verifies on SAR Duty's verify site, and
  anyone can sign up a team on SAR Duty Records, so a SAR Duty admin checks a team before
  it may issue them: when turning on its cards, or when adding it to an organization
  (#512). So a SAR Duty admin acts, from the team's admin page, /admin/teams/:id (#513),
  or one of the team's own organization admins, from its page in the organization. Anyone
  else is refused, which also stops someone removed, or a team taken out of the
  organization, while the page is still open.

  Turning it off cancels every live card on the team, and phones holding one are told to
  fetch the voided pass, so turning it back on never wakes old cards. Either way the
  team's team admins get an email.
  """

  import Ecto.Query

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

  # The team's organization now, not as the page loaded it: a team removed from the
  # organization while its page is open is no longer theirs.
  def allowed?(%Team{id: id}, %User{} = user) do
    organization_id =
      Team |> where([t], t.id == ^id) |> select([t], t.organization_id) |> Repo.one()

    OrganizationAdmin.admin_of?(organization_id, user)
  end

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
