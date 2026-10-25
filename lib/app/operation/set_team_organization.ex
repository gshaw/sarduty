defmodule App.Operation.SetTeamOrganization do
  @moduledoc """
  Adds a team to an organization, or removes it (#512). Only a SAR Duty admin does this,
  from the organization's space: adding a team is when they check it is real, since the
  organization's admins can then turn on its ID cards (docs/member-cards.md).

  Adding takes only a team in no organization, so it never moves a team from another
  one: the update matches `organization_id IS NULL`, so two adds can't race. A team whose
  own hours tags would repeat the organization's is refused. Either way the team's
  passes are rebuilt, since the back of the pass names the organization, an event
  records it, and its team admins get an email. Its ID cards stay on or off as they are.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Mailer.TeamAdminMailer
  alias App.Model.Activity
  alias App.Model.Event
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Repo
  alias App.Worker.PushPassUpdatesWorker

  @doc """
  `{:ok, team}`, or `{:error, reason}`: `:forbidden` for anyone but a SAR Duty admin,
  `:taken` when the team is in an organization already, `:not_in_organization` when it
  is not in the one it is removed from, or `{:hours_tag, text}` when the tags clash.
  """
  def call(team, organization, user, now \\ DateTime.utc_now())

  def call(%Team{}, _organization, %User{is_admin: false}, _now), do: {:error, :forbidden}

  def call(%Team{} = team, %Organization{} = organization, %User{} = user, now) do
    with :ok <- check_hours_tags(team, organization),
         {1, _rows} <-
           Team
           |> where([t], t.id == ^team.id and is_nil(t.organization_id))
           |> Repo.update_all(set: [organization_id: organization.id]) do
      after_change(team, organization, :organization_team_added, user, now)
    else
      {0, _rows} -> {:error, :taken}
      error -> error
    end
  end

  def call(%Team{organization_id: nil}, nil, %User{}, _now), do: {:error, :not_in_organization}

  def call(%Team{} = team, nil, %User{} = user, now) do
    organization = Repo.get!(Organization, team.organization_id)

    case Team
         |> where([t], t.id == ^team.id and t.organization_id == ^organization.id)
         |> Repo.update_all(set: [organization_id: nil]) do
      {1, _rows} -> after_change(team, organization, :organization_team_removed, user, now)
      {0, _rows} -> {:error, :not_in_organization}
    end
  end

  @doc """
  The clash between the organization's hours tags and the team's own, as text, or nil:
  `Activity.repeated_hours_tag/1` on the team's tags as they would be.
  """
  def hours_tag_clash(%Team{} = team, %Organization{} = organization) do
    case %{team | organization: organization}
         |> Activity.hours_tags()
         |> Activity.repeated_hours_tag() do
      nil ->
        nil

      {kind, _text} ->
        "#{team.name}'s own tag for #{Activity.hours_kind_name(kind)} repeats one of #{organization.short_name}'s. Change it on its Hours tags page first."
    end
  end

  defp check_hours_tags(team, organization) do
    case hours_tag_clash(team, organization) do
      nil -> :ok
      text -> {:error, {:hours_tag, text}}
    end
  end

  defp after_change(team, organization, kind, user, now) do
    team = Team |> Repo.get!(team.id) |> Repo.preload(:organization)

    Event.record!(kind,
      team_id: team.id,
      user_id: user.id,
      data: %{organization_id: organization.id}
    )

    PushPassUpdatesWorker.enqueue(team)

    case kind do
      :organization_team_added -> TeamAdminMailer.deliver_joined(team, organization, now)
      :organization_team_removed -> TeamAdminMailer.deliver_left(team, organization, now)
    end

    {:ok, team}
  end
end
