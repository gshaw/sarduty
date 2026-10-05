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
  schema "no_shows" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :member, Member
    belongs_to :followed_up_by_user, User
    field :followed_up_at, :utc_datetime_usec
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

  @doc "Ticks or unticks a no-show, found through the team. Nil when it isn't the team's."
  def set_followed_up(%Team{} = team, id, followed_up, %User{} = user, now) do
    case Repo.get_by(NoShow, id: id, team_id: team.id) do
      nil ->
        nil

      no_show ->
        changes =
          if followed_up,
            do: [followed_up_at: now, followed_up_by_user_id: user.id],
            else: [followed_up_at: nil, followed_up_by_user_id: nil]

        no_show |> change(changes) |> Repo.update!()
    end
  end
end
