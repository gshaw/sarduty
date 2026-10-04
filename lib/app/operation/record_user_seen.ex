defmodule App.Operation.RecordUserSeen do
  @moduledoc """
  Stamps `users.last_seen_at` when someone opens a team page, so `/admin` can show which
  teams still use SAR Duty. Writes at most once an hour per user, and never for admins,
  whose visits say nothing about a team.

  Also remembers the team opened, for everyone, so logging in lands on it.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Repo

  @interval_seconds 60 * 60

  def call(%User{} = user, team_id, now \\ DateTime.utc_now()) do
    changes =
      if(due?(user, now), do: [last_seen_at: DateTime.truncate(now, :second)], else: []) ++
        if user.last_team_id == team_id, do: [], else: [last_team_id: team_id]

    # update_all rather than a changeset, so a page view doesn't bump updated_at.
    if changes != [], do: User |> where(id: ^user.id) |> Repo.update_all(set: changes)

    :ok
  end

  def due?(%User{is_admin: true}, _now), do: false
  def due?(%User{last_seen_at: nil}, _now), do: true

  def due?(%User{last_seen_at: last_seen_at}, now),
    do: DateTime.diff(now, last_seen_at) >= @interval_seconds
end
