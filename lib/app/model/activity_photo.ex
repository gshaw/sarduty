defmodule App.Model.ActivityPhoto do
  use App, :model

  alias App.Accounts.User
  alias App.Field.TrimmedString
  alias App.Model.Activity
  alias App.Model.ActivityPhoto
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  # A photo someone added to an activity (#1032): an exercise or an event, never an
  # incident (Activity.takes_photos?/1). It waits until a team admin accepts it, and
  # then everyone on the team sees it. A waiting photo is seen only by team admins and
  # the member who added it: `visible/2` is that rule, for every list and for the file
  # route.
  #
  # `member` is who added it, or nil for a team admin with no member row, and
  # `added_by_user` their login. `caption` and `may_post` are the send's: one caption
  # and one permission for the photos sent together.
  #
  # The files are in the file store, never here: `key/2` names each of the three, from
  # `file_token`. App.Operation.AddActivityPhotos puts them, and
  # App.Operation.DeleteActivityPhotos takes them away with the row.
  @sizes [:original, :show, :tile]

  schema "activity_photos" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :member, Member
    belongs_to :added_by_user, User
    belongs_to :accepted_by_user, User
    field :status, Ecto.Enum, values: [:waiting, :accepted], default: :waiting
    field :file_token, :string
    # The original's size, turned the way the camera held it.
    field :width, :integer
    field :height, :integer
    field :caption, TrimmedString, redact: true
    # Whether the team may post it on its website and social media. No unless the
    # person who added it checked the box.
    field :may_post, :boolean, default: false
    field :accepted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  The photo's three files: `:original`, the photo at its full size; `:show`, up to
  2048 px; and `:tile`, up to 600 px. Each is a JPEG with no location or camera data.
  """
  def sizes, do: @sizes

  @doc "A new `file_token`: random, so a key says nothing and is never used twice."
  def new_token, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  @doc "The file store's key for one of the photo's files, under its team's prefix."
  def key(%ActivityPhoto{team_id: team_id, file_token: token}, size)
      when size in @sizes and is_binary(token),
      do: "#{Team.file_prefix(team_id)}/activity-photos/#{token}/#{size}.jpg"

  @doc "Each of the photo's files with its key, as `{size, key}`."
  def keys(%ActivityPhoto{} = photo), do: for(size <- @sizes, do: {size, key(photo, size)})

  @doc """
  The photos `viewer` sees: accepted ones, and waiting ones for a team admin or the
  member who added them. `viewer` is `%{team_admin?:, member:}`, the member logged in or
  nil. A team admin viewing as a member is that member.
  """
  def visible(query, %{team_admin?: true}), do: query

  def visible(query, %{member: %Member{id: member_id}}),
    do: where(query, [p], p.status == :accepted or p.member_id == ^member_id)

  def visible(query, _viewer), do: where(query, [p], p.status == :accepted)

  @doc "Pure. visible/2 for one photo."
  def visible?(%ActivityPhoto{}, %{team_admin?: true}), do: true
  def visible?(%ActivityPhoto{status: :accepted}, _viewer), do: true

  def visible?(%ActivityPhoto{member_id: member_id}, %{member: %Member{id: id}}),
    do: member_id == id

  def visible?(%ActivityPhoto{}, _viewer), do: false

  @doc """
  The activity's photos `viewer` sees, newest first, each with who added it: the Photos
  tab. Waiting ones are in the list too, for whoever sees them.
  """
  def for_activity(%Activity{id: activity_id, team_id: team_id}, viewer) do
    ActivityPhoto
    |> where([p], p.team_id == ^team_id and p.activity_id == ^activity_id)
    |> visible(viewer)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> preload([:member, :added_by_user])
    |> Repo.all()
  end

  @doc """
  One of the team's photos `viewer` sees, with its activity, for the file route. A
  member never gets one on an activity that is deleted, as they never get its page, and
  nobody gets one on an activity that no longer takes photos. Raises when there is
  none, so the route is not found.
  """
  def find_visible!(%Team{id: team_id}, id, %{team_admin?: team_admin?} = viewer) do
    ActivityPhoto
    |> where([p], p.team_id == ^team_id and p.id == ^id)
    |> join_activity(team_id)
    |> where([activity: a], ^team_admin? or is_nil(a.deleted_at))
    |> visible(viewer)
    |> preload([activity: a], activity: a)
    |> Repo.one!()
  end

  # Each photo's activity as `:activity`: the team's own, and still of a kind that
  # takes photos. One that D4H turned into an incident keeps its photos out of sight.
  defp join_activity(query, team_id) do
    query
    |> join(:inner, [p], a in assoc(p, :activity), as: :activity)
    |> where([activity: a], a.team_id == ^team_id)
    |> where([activity: a], a.activity_kind in ^Activity.photo_kinds())
  end

  @doc """
  The team's photos waiting for a team admin, each with its activity and who added it:
  activities newest first, and in each the oldest photo first. Photos' Waiting view.
  Never a deleted activity's, which no list shows, or one that no longer takes photos.
  """
  def get_waiting(%Team{} = team) do
    team
    |> waiting_query()
    |> order_by([p, activity: a], desc: a.started_at, desc: a.id, asc: p.inserted_at, asc: p.id)
    |> preload([activity: a], [:member, :added_by_user, activity: a])
    |> Repo.all()
  end

  @doc "How many `get_waiting/1` lists: what Needs attention counts."
  def count_waiting(%Team{} = team), do: team |> waiting_query() |> Repo.aggregate(:count)

  defp waiting_query(%Team{id: team_id}) do
    ActivityPhoto
    |> where([p], p.team_id == ^team_id and p.status == :waiting)
    |> join_activity(team_id)
    |> where([activity: a], is_nil(a.deleted_at))
  end

  @doc "How many of the activity's photos wait: the count on its Photos tab, for team admins."
  def count_waiting_on(%Activity{id: activity_id, team_id: team_id}) do
    ActivityPhoto
    |> where([p], p.team_id == ^team_id and p.activity_id == ^activity_id)
    |> where([p], p.status == :waiting)
    |> Repo.aggregate(:count)
  end

  @doc """
  The activity's waiting photos among `ids`, which come from the browser: only the
  team's, on this activity, and still waiting. What Accept and Delete change.
  """
  def waiting_among(%Team{id: team_id}, %Activity{id: activity_id}, ids) when is_list(ids) do
    ActivityPhoto
    |> where([p], p.team_id == ^team_id and p.activity_id == ^activity_id)
    |> where([p], p.status == :waiting and p.id in ^ids)
    |> order_by([p], asc: p.id)
  end
end
