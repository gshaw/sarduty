defmodule App.Model.ActivityUpdate do
  use App, :model

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.ActivityUpdate
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  # An update a team admin emailed to a member on an activity (#609): their own message,
  # with where the member stands. A send's rows share their `sent_at` and message.
  # Queued waits for its job, App.Worker.SendActivityUpdateWorker. Failed is Cloudflare
  # refusing it every time, or the activity starting first, with why in `error`. A
  # `:removal` is the message to a signed up member taken off the activity (#704).
  schema "activity_updates" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :member, Member
    belongs_to :sent_by_user, User
    field :message, :string, redact: true
    field :sent_at, :utc_datetime_usec
    field :status, Ecto.Enum, values: [:queued, :sent, :failed]
    field :kind, Ecto.Enum, values: [:update, :removal], default: :update
    field :error, :string
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The activity's updates, with who sent them, oldest first."
  def for_activity(%Activity{} = activity) do
    ActivityUpdate
    |> where([u], u.activity_id == ^activity.id and u.team_id == ^activity.team_id)
    |> order_by([u], asc: u.sent_at, asc: u.id)
    |> preload(:sent_by_user)
    |> Repo.all()
  end

  @doc """
  A queued update, with its team, activity, member, and sender, or nil once it's sent,
  failed, or gone. The activity and member are found through the update's team.
  """
  def get_queued(id) do
    ActivityUpdate
    |> join(:inner, [u], t in assoc(u, :team))
    |> join(:inner, [u, t], a in assoc(u, :activity), on: a.team_id == t.id)
    |> join(:inner, [u, t], m in assoc(u, :member), on: m.team_id == t.id)
    |> where([u], u.id == ^id and u.status == :queued)
    |> preload([u, t, a, m], [:sent_by_user, team: t, activity: a, member: m])
    |> Repo.one()
  end

  @doc "Marks an update sent."
  def sent!(%ActivityUpdate{} = update),
    do: update |> change(status: :sent, error: nil) |> Repo.update!()

  @doc "Marks an update failed, with Cloudflare's answer or another reason."
  def fail!(%ActivityUpdate{} = update, error),
    do: update |> change(status: :failed, error: String.slice(error, 0, 255)) |> Repo.update!()
end
