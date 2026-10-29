defmodule App.Model.NoShow do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Member
  alias App.Model.NoShow
  alias App.Model.Team
  alias App.Repo

  # A member who signed up for an activity and did not arrive, marked absent in D4H from
  # the door's attendance. A team admin checks they're OK, then ticks it followed up.
  # Cleared when they turn out attended after all.
  schema "no_shows" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :member, Member
    belongs_to :followed_up_by_user, User
    field :followed_up_at, :utc_datetime_usec
    # What they heard, set with the tick (#650).
    field :note, :string, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  @doc "Records the member as a no-show. Sending again doesn't add a second row."
  def record!(%Activity{} = activity, %Member{team_id: team_id} = member)
      when team_id == activity.team_id do
    Repo.insert!(
      %NoShow{team_id: team_id, activity_id: activity.id, member_id: member.id},
      on_conflict: :nothing,
      conflict_target: [:activity_id, :member_id]
    )
  end

  @doc """
  Clears the member's no-show on the activity, once they're attended there after all:
  sent from the door, or changed in D4H or Records and seen by the sync (#648).
  """
  def clear(activity_id, member_id) do
    NoShow
    |> where([n], n.activity_id == ^activity_id and n.member_id == ^member_id)
    |> Repo.delete_all()
  end

  @doc "The activity's no-shows with their members, by name."
  def get_all(%Activity{} = activity) do
    NoShow
    |> where([n], n.activity_id == ^activity.id and n.team_id == ^activity.team_id)
    |> join(:inner, [n], m in assoc(n, :member))
    |> where([n, m], m.team_id == ^activity.team_id)
    |> order_by([n, m], asc: m.name)
    |> preload([:member, :followed_up_by_user])
    |> Repo.all()
  end

  @doc """
  Marks a no-show followed up by `user` at `now` with an optional `note`, or not with
  `nil`, found through the team. Nil when it isn't the team's.
  """
  def set_followed_up(%Team{} = team, id, followed_up, %User{} = user, now) do
    case Repo.get_by(NoShow, id: id, team_id: team.id) do
      nil ->
        nil

      no_show ->
        changes =
          case followed_up do
            {:note, note} -> [followed_up_at: now, followed_up_by_user_id: user.id, note: note]
            nil -> [followed_up_at: nil, followed_up_by_user_id: nil, note: nil]
          end

        no_show |> change(changes) |> Repo.update!() |> Repo.preload(:followed_up_by_user)
    end
  end

  @doc """
  Deletes a no-show that wasn't one, found through the team (#650): no history, as the
  history rule in docs/change-history.md says. Nil when it isn't the team's.
  """
  def remove(%Team{} = team, id) do
    case Repo.get_by(NoShow, id: id, team_id: team.id) do
      nil -> nil
      no_show -> Repo.delete!(no_show)
    end
  end

  @doc """
  Activities that started from `since` to `now` with no-shows nobody has followed up, as
  `%{id:, title:, count:}`, oldest first (#650).
  """
  def to_follow_up(%Team{} = team, since, now) do
    NoShow
    |> where([n], n.team_id == ^team.id and is_nil(n.followed_up_at))
    |> at_activities(team.id, since, now)
    |> group_by([n, a], a.id)
    |> order_by([n, a], asc: a.started_at, asc: a.id)
    |> select([n, a], %{id: a.id, title: a.title, count: count(n.id)})
    |> Repo.all()
  end

  @doc "The member's no-shows at activities that started in `year`, newest first (#650)."
  def for_member(%Member{} = member, year, timezone) do
    {start, finish} = Service.YearRange.bounds(year, timezone)

    NoShow
    |> where([n], n.team_id == ^member.team_id and n.member_id == ^member.id)
    |> at_activities(member.team_id, start, finish)
    |> order_by([n, a], desc: a.started_at, desc: n.id)
    |> preload([n, a], activity: a, followed_up_by_user: [])
    |> Repo.all()
  end

  # The team's activities not deleted that started from `from` until `to`, joined as `a`.
  defp at_activities(query, team_id, from, to) do
    query
    |> join(:inner, [n], a in assoc(n, :activity))
    |> where([n, a], a.team_id == ^team_id and is_nil(a.deleted_at))
    |> where([n, a], a.started_at >= ^from and a.started_at < ^to)
  end
end
