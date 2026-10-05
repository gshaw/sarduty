defmodule App.Model.AttendanceLink do
  use App, :model

  alias App.Accounts.User
  alias App.Field.EncryptedString
  alias App.Model.Activity
  alias App.Model.AttendanceLink
  alias App.Model.Team
  alias App.Repo

  # A link a team admin makes so someone at the door can take attendance for one
  # activity, with no account. The token is the secret: whoever holds the link can record
  # scans and see the team's member names, and nothing else. It works until it's closed
  # or a day after the activity ends.
  schema "attendance_links" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :created_by_user, User
    field :token, EncryptedString, redact: true
    field :token_hash, :string
    field :closed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @open_hours_after_finish 24

  def generate_token, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  def hash_token(token),
    do: :sha256 |> :crypto.hash(token) |> Base.url_encode64(padding: false)

  @doc "When the link stops working, unless it's closed first."
  def expires_at(%Activity{finished_at: finished_at}),
    do: DateTime.add(finished_at, @open_hours_after_finish, :hour)

  def open?(%AttendanceLink{closed_at: nil, activity: %Activity{} = activity}, now),
    do: DateTime.before?(now, expires_at(activity))

  def open?(%AttendanceLink{}, _now), do: false

  def insert!(%AttendanceLink{} = link), do: Repo.insert!(link)

  @doc "The link for `token`, with its activity and team, or nil."
  def find_by_token(token) when is_binary(token) do
    AttendanceLink
    |> where([l], l.token_hash == ^hash_token(token))
    |> preload(activity: :team)
    |> Repo.one()
  end

  def find_by_token(_token), do: nil

  @doc "The activity's link that isn't closed, or nil. Old links are closed when a new one is made."
  def find_current(%Team{} = team, %Activity{} = activity) do
    AttendanceLink
    |> where([l], l.team_id == ^team.id and l.activity_id == ^activity.id)
    |> where([l], is_nil(l.closed_at))
    |> order_by([l], desc: l.id)
    |> limit(1)
    |> preload(activity: :team)
    |> Repo.one()
  end

  def close_all!(%Team{} = team, %Activity{} = activity, now) do
    AttendanceLink
    |> where([l], l.team_id == ^team.id and l.activity_id == ^activity.id)
    |> where([l], is_nil(l.closed_at))
    |> Repo.update_all(set: [closed_at: now, updated_at: now])
  end
end
