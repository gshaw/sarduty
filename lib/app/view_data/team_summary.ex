defmodule App.ViewData.TeamSummary do
  @moduledoc """
  Counts about many teams at once, for lists of teams: `/admin` and an organization's
  Teams page (#512). Each is a few grouped queries for every team, except
  `untagged_counts/2`, which reuses the team dashboard's count, a few queries per team.
  Counts only: no names, emails, or numbers leave here except `team_admin_emails/2`,
  which only SAR Duty admin pages show.
  """
  import Ecto.Query

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Model.TeamLoginGrant
  alias App.Repo
  alias App.ViewData.TeamDashboardViewData

  @doc """
  Who reaches each team as a team admin, by lowercase email, A to Z: the D4H Owners and
  Editors with an email that `Member.get_managers/2` counts, and its login grants. One
  entry per email. `%{team_id => [email]}`, with every team in it.
  """
  def team_admin_emails(teams, now) do
    ids = Enum.map(teams, & &1.id)

    by_team =
      (manager_emails(teams, now) ++ grant_emails(ids))
      |> Enum.group_by(&elem(&1, 0), &normalize(elem(&1, 1)))

    Map.new(ids, &{&1, by_team |> Map.get(&1, []) |> Enum.uniq() |> Enum.sort()})
  end

  defp manager_emails(teams, now) do
    ids = Enum.map(teams, & &1.id)

    Member
    |> where([m], m.team_id in ^ids and not is_nil(m.email))
    |> Member.managers_query(now)
    |> select([m], {m.team_id, m.email})
    |> Repo.all()
  end

  defp grant_emails(ids) do
    TeamLoginGrant
    |> where([g], g.team_id in ^ids)
    |> select([g], {g.team_id, g.email})
    |> Repo.all()
  end

  @doc """
  Everyone who reaches one team as a team admin, one row per email, A to Z, for its
  SAR Duty admin page (#513): `%{email:, roles:, grant:, last_seen_at:}`. `roles` are its
  D4H access levels, such as "D4H Owner", and `grant` its login grant, or nil. An email
  that is both is one row.
  """
  def team_admin_rows(%Team{} = team, now) do
    roles = manager_roles(team, now)
    grants = team |> TeamLoginGrant.get_for_team() |> Map.new(&{&1.email, &1})
    emails = Enum.uniq(Map.keys(roles) ++ Map.keys(grants))
    seen = last_seen_by_email(emails)

    for email <- Enum.sort(emails) do
      %{
        email: email,
        roles: roles |> Map.get(email, []) |> Enum.uniq(),
        grant: grants[email],
        last_seen_at: seen[email]
      }
    end
  end

  # Each manager's email and their access, such as "D4H Owner".
  defp manager_roles(team, now) do
    service = D4H.service_name(team)

    team
    |> Member.get_managers(now)
    |> Enum.reject(&is_nil(&1.email))
    |> Enum.group_by(
      &normalize(&1.email),
      &"#{service} #{Member.permission_label(&1.d4h_permission)}"
    )
  end

  defp normalize(email), do: email |> String.trim() |> String.downcase()

  defp last_seen_by_email(emails) do
    User
    |> where([u], fragment("lower(?)", u.email) in ^emails and not is_nil(u.last_seen_at))
    |> select([u], {fragment("lower(?)", u.email), u.last_seen_at})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The last time a team admin opened one of each team's pages, or nil: the latest
  `users.last_seen_at` among its team admins. RecordUserSeen stamps it for team admins
  only, never members or SAR Duty admins. `%{team_id => DateTime | nil}`.
  """
  def last_seen(teams, now), do: last_seen_from(team_admin_emails(teams, now))

  @doc "last_seen/2 from team_admin_emails/2 already loaded."
  def last_seen_from(emails_by_team) do
    emails = emails_by_team |> Map.values() |> List.flatten() |> Enum.uniq()

    seen = last_seen_by_email(emails)

    Map.new(emails_by_team, fn {team_id, emails} ->
      latest =
        emails
        |> Enum.map(&seen[&1])
        |> Enum.reject(&is_nil/1)
        |> Enum.max(DateTime, fn -> nil end)

      {team_id, latest}
    end)
  end

  @doc """
  Each team's current members who are people and not retiring (#514), as the team's own
  Dashboard counts them. `%{team_id => count}`.
  """
  def member_counts(teams, now) do
    ids = Enum.map(teams, & &1.id)

    Member
    |> where([m], m.team_id in ^ids)
    |> Member.current_query(now)
    |> Member.counted_query()
    |> group_by([m], m.team_id)
    |> select([m], {m.team_id, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Each team's live ID cards. `%{team_id => count}`."
  def card_counts, do: MemberCard.count_live_by_team()

  @doc "Tax credit letters made for `year`, by team. `%{team_id => count}`."
  def letter_counts(teams, year) do
    ids = Enum.map(teams, & &1.id)

    TaxCreditLetter
    |> join(:inner, [l], m in Member, on: m.id == l.member_id)
    |> where([l, m], m.team_id in ^ids and l.year == ^year)
    |> group_by([l, m], m.team_id)
    |> select([l, m], {m.team_id, count(l.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Published activities with no hours tag in the open years, by team, summed over the
  years, as the team dashboard counts them. `%{team_id => count}`.
  """
  def untagged_counts(teams, now) do
    Map.new(teams, fn team ->
      count =
        team |> TeamDashboardViewData.untagged_rows(now) |> Enum.map(& &1.count) |> Enum.sum()

      {team.id, count}
    end)
  end
end
