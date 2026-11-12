defmodule App.Model.ActivityPhotoAsk do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.ActivityPhotoAsk
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  # A team admin asking a member who attended an activity for their photos of it
  # (#1034): who asked, when, and their message. A member has one ask for an activity:
  # asking again moves its date and sends another email. It never closes: its link works
  # for 30 days from its email, however many photos the member adds. `email_status` is
  # how the last email went, for its job, App.Worker.SendPhotoAskWorker.
  schema "activity_photo_asks" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :member, Member
    belongs_to :asked_by_user, User
    # The team admin's own words, at the top of the email.
    field :message, :string, redact: true
    field :asked_at, :utc_datetime_usec
    field :email_status, Ecto.Enum, values: [:queued, :sent, :failed], default: :queued
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The activity's asks, one for each member asked."
  def for_activity(%Activity{id: activity_id, team_id: team_id}) do
    ActivityPhotoAsk
    |> where([a], a.team_id == ^team_id and a.activity_id == ^activity_id)
    |> Repo.all()
  end

  @doc """
  Pure. The last time the team asked, from the activity's asks: `%{count:, asked_at:}`,
  how many members that send asked and when, or nil when nobody was asked. Every ask of
  one send has the same `asked_at`.
  """
  def last([]), do: nil

  def last(asks) when is_list(asks) do
    asked_at = asks |> Enum.map(& &1.asked_at) |> Enum.max(DateTime)

    %{
      count: Enum.count(asks, &(DateTime.compare(&1.asked_at, asked_at) == :eq)),
      asked_at: asked_at
    }
  end

  @doc """
  An ask with its team, activity, member, and who asked, or nil. The activity and the
  member are found through the ask's team.
  """
  def get(id) do
    query =
      from a in ActivityPhotoAsk,
        join: t in assoc(a, :team),
        join: m in assoc(a, :member),
        on: m.team_id == t.id,
        join: v in assoc(a, :activity),
        on: v.team_id == t.id,
        where: a.id == ^id,
        preload: [:asked_by_user, team: t, member: m, activity: v]

    Repo.one(query)
  end

  @doc "Stores how the ask's email went."
  def set_email_status!(%ActivityPhotoAsk{} = ask, status),
    do: ask |> change(email_status: status) |> Repo.update!()
end
