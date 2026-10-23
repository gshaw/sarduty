defmodule App.Model.Reminder do
  use App, :model

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Member
  alias App.Model.Reminder
  alias App.Model.Team
  alias App.Repo

  # A reminder emailed to a member about an activity they haven't replied to (#444).
  # Round 1, then round 2 (Ask again), at most one each per member and activity. A send's
  # rows share their `sent_at`, so the rows of one batch are those with its time. Failed
  # is Cloudflare refusing it, with its answer in `error`.
  schema "reminders" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :member, Member
    belongs_to :sent_by_user, User
    field :sent_at, :utc_datetime_usec
    field :round, :integer
    field :status, Ecto.Enum, values: [:sent, :failed]
    field :error, :string
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The activity's reminders, with who sent them, oldest first."
  def for_activity(%Activity{} = activity) do
    Reminder
    |> where([r], r.activity_id == ^activity.id and r.team_id == ^activity.team_id)
    |> order_by([r], asc: r.sent_at, asc: r.id)
    |> preload(:sent_by_user)
    |> Repo.all()
  end

  @doc """
  Records a reminder about to go out, as sent. `nil` when the member has that round
  already, such as when two team admins send at once: then it isn't sent again.
  """
  def insert(%Reminder{} = reminder) do
    case Repo.insert(reminder,
           on_conflict: :nothing,
           conflict_target: [:activity_id, :member_id, :round]
         ) do
      {:ok, %Reminder{id: nil}} -> nil
      {:ok, reminder} -> reminder
    end
  end

  @doc "Marks a reminder failed, with Cloudflare's answer."
  def fail!(%Reminder{} = reminder, error),
    do: reminder |> change(status: :failed, error: String.slice(error, 0, 255)) |> Repo.update!()
end
