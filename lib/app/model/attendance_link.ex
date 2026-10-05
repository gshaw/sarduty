defmodule App.Model.AttendanceLink do
  use App, :model

  alias App.Accounts.User
  alias App.Field.EncryptedString
  alias App.Model.Activity
  alias App.Model.AttendanceLink
  alias App.Model.ShortLink
  alias App.Model.Team
  alias App.Repo

  # A link a team admin makes so someone at the door can take attendance for one
  # activity, with no account. The token is the secret: whoever holds the link can record
  # scans and see the team's member names, and nothing else. It opens when it's made and
  # works until it's closed: by a send to D4H, by a team admin, or by a new link. 30 days
  # after it's made it stops anyway, so a forgotten link dies. The limit counts from the
  # link, not the activity, so a late catch-up from a paper list still works.
  schema "attendance_links" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :created_by_user, User
    belongs_to :short_link, ShortLink
    field :token, EncryptedString, redact: true
    field :token_hash, :string
    field :closed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @open_days 30

  def generate_token, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  def hash_token(token),
    do: :sha256 |> :crypto.hash(token) |> Base.url_encode64(padding: false)

  @doc "When the link stops working, unless it's closed first: #{@open_days} days after it's made."
  def expires_at(%AttendanceLink{inserted_at: made_at}), do: expires_at(made_at)
  def expires_at(%DateTime{} = made_at), do: DateTime.add(made_at, @open_days, :day)

  def open?(%AttendanceLink{closed_at: nil} = link, now),
    do: DateTime.before?(now, expires_at(link))

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
    |> preload([:short_link, activity: :team])
    |> Repo.one()
  end

  @doc "Closes the activity's open links and deletes their short links."
  def close_all!(%Team{} = team, %Activity{} = activity, now) do
    open =
      AttendanceLink
      |> where([l], l.team_id == ^team.id and l.activity_id == ^activity.id)
      |> where([l], is_nil(l.closed_at))

    {:ok, result} =
      Repo.transaction(fn ->
        short_link_ids =
          open |> where([l], not is_nil(l.short_link_id)) |> select([l], l.short_link_id)

        ShortLink.delete_all!(team, Repo.all(short_link_ids))
        Repo.update_all(open, set: [closed_at: now, updated_at: now])
      end)

    result
  end
end
