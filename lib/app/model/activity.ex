defmodule App.Model.Activity do
  use App, :model

  import Ecto.Query

  alias App.Field.TrimmedString
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Repo

  @default_hours_tags %{primary: "Primary Hours", secondary: "Secondary Hours", other: nil}
  @hours_kinds [:primary, :secondary, :other]

  @doc """
  The D4H tags that say which hours an activity counts for, as `%{primary: tag,
  secondary: tag, other: tag}`. Other is for activities that count for no hours, and is
  nil when nobody names one. A team's organization names each tag (#289); a team names
  the ones its organization leaves blank (#323); otherwise "Primary Hours" and
  "Secondary Hours". Uses the team's organization when it is preloaded, and reads just
  its tags when it isn't.
  """
  def hours_tags(%Organization{} = organization),
    do: Map.merge(@default_hours_tags, organization_hours_tags(organization), &pick/3)

  def hours_tags(%Team{} = team) do
    team_tags = %{
      primary: team.primary_hours_tag,
      secondary: team.secondary_hours_tag,
      other: team.other_hours_tag
    }

    @default_hours_tags
    |> Map.merge(team_tags, &pick/3)
    |> Map.merge(organization_hours_tags(team), &pick/3)
  end

  defp pick(_kind, default, nil), do: default
  defp pick(_kind, _default, tag), do: tag

  @doc """
  The hours tags the team's organization names, as `%{kind => tag or nil}`. A team can
  name only the ones that are nil.
  """
  def organization_hours_tags(%Organization{} = organization) do
    %{
      primary: organization.primary_hours_tag,
      secondary: organization.secondary_hours_tag,
      other: organization.other_hours_tag
    }
  end

  def organization_hours_tags(%Team{organization: %Organization{} = organization}),
    do: organization_hours_tags(organization)

  def organization_hours_tags(%Team{organization_id: nil}), do: Map.new(@hours_kinds, &{&1, nil})

  def organization_hours_tags(%Team{organization_id: organization_id}) do
    Organization
    |> where([o], o.id == ^organization_id)
    |> select([o], %Organization{
      primary_hours_tag: o.primary_hours_tag,
      secondary_hours_tag: o.secondary_hours_tag,
      other_hours_tag: o.other_hours_tag
    })
    |> Repo.one!()
    |> organization_hours_tags()
  end

  @doc """
  The first hours kind whose tag repeats an earlier kind's, ignoring case, with the text
  to show on it; or nil when all differ.
  """
  def repeated_hours_tag(hours_tags) do
    pairs = [{:secondary, :primary}, {:other, :primary}, {:other, :secondary}]

    Enum.find_value(pairs, fn {kind, earlier} ->
      if same_tag?(hours_tags[kind], hours_tags[earlier]),
        do: {kind, "Use a different tag from #{earlier} hours."}
    end)
  end

  @doc "The organization's or team's field for an hours kind."
  def hours_tag_field(:primary), do: :primary_hours_tag
  def hours_tag_field(:secondary), do: :secondary_hours_tag
  def hours_tag_field(:other), do: :other_hours_tag

  defp same_tag?(nil, _tag), do: false
  defp same_tag?(_tag, nil), do: false
  defp same_tag?(tag, other), do: String.downcase(tag) == String.downcase(other)

  @doc """
  Whether the tags say which hours the activity counts for: primary, secondary, or the
  other tag for none.
  """
  def hours_tagged?(tags, hours_tags) do
    tags = tags || []
    Enum.any?(@hours_kinds, &(hours_tags[&1] && hours_tags[&1] in tags))
  end

  @doc "Which hours the tags count for: `:primary`, `:secondary`, or nil. Primary wins."
  def counts_as(tags, %{primary: primary, secondary: secondary}) do
    tags = tags || []

    cond do
      primary in tags -> :primary
      secondary in tags -> :secondary
      true -> nil
    end
  end

  def null_island, do: "0.00000,0.00000"

  @doc "The activity's latitude and longitude, or nil when D4H has none or 0,0."
  def pin(%{coordinate: coordinate}) do
    if coordinate in [nil, "", null_island()], do: nil, else: coordinate
  end

  schema "activities" do
    belongs_to :team, Team
    has_many :attendances, Attendance, where: [status: "attending"]
    has_many :members, through: [:attendances, :member]
    field :d4h_activity_id, :integer
    field :ref_id, :string
    field :tracking_number, :string
    field :is_published, :boolean
    field :title, TrimmedString
    field :description, TrimmedString
    field :address, TrimmedString
    field :coordinate, :string
    field :activity_kind, :string
    field :hours_kind, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :tags, {:array, :string}
    # Set by the refresh when D4H stops listing the activity. Deleted activities are kept
    # for their attendance scans, and left out of every list.
    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%Activity{}, params)

  # Rows are copies of D4H, so they take whatever D4H holds: no length or format
  # rules. A refresh that rejects one row fails for the whole team.
  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :team_id,
      :d4h_activity_id,
      :ref_id,
      :tracking_number,
      :is_published,
      :title,
      :description,
      :address,
      :coordinate,
      :activity_kind,
      :hours_kind,
      :started_at,
      :finished_at,
      :tags
    ])
    |> validate_required([
      :team_id,
      :d4h_activity_id,
      :is_published,
      :title,
      :activity_kind,
      :started_at,
      :finished_at
    ])
    |> update_change(:tags, &sort_tags/1)
  end

  @doc """
  Tags in the order they're stored: sorted, since D4H's order means nothing and changes
  when tags are set. Two copies with the same tags then compare equal (#358).
  """
  def sort_tags(nil), do: nil
  def sort_tags(tags), do: Enum.sort(tags)

  def get_all(team_id) do
    Activity
    |> where([r], r.team_id == ^team_id)
    |> not_deleted()
    |> order_by([r], desc: r.started_at)
    |> Repo.all()
  end

  def find!(team, id), do: Repo.get_by!(Activity, id: id, team_id: team.id)

  def scope(q, team_id: team_id), do: where(q, team_id: ^team_id)

  @doc "Leaves out activities deleted in D4H."
  def not_deleted(query), do: where(query, [r], is_nil(r.deleted_at))

  def deleted?(%Activity{deleted_at: deleted_at}), do: deleted_at != nil

  @attendance_window_hours 2

  def attendance_window_hours, do: @attendance_window_hours

  @doc """
  When members take attendance (#475): from #{@attendance_window_hours} hours before the
  activity starts until #{@attendance_window_hours} hours after it ends.
  """
  def attendance_window(%Activity{started_at: started_at, finished_at: finished_at}) do
    seconds = @attendance_window_hours * 3600
    {DateTime.add(started_at, -seconds), DateTime.add(finished_at, seconds)}
  end

  def attendance_window?(%Activity{} = activity, now) do
    {opens_at, closes_at} = attendance_window(activity)
    not DateTime.before?(now, opens_at) and not DateTime.after?(now, closes_at)
  end

  @doc """
  Whether someone who reaches the team's pages may take attendance now: a team admin at
  any time, to catch up from a paper list, and a member during attendance_window?/2.
  Nobody on a deleted activity. Decides both whether Take attendance shows and whether a
  scan is saved.
  """
  def take_attendance?(%Activity{deleted_at: %DateTime{}}, _team_admin?, _now), do: false
  def take_attendance?(%Activity{}, true, _now), do: true
  def take_attendance?(%Activity{} = activity, false, now), do: attendance_window?(activity, now)

  @doc """
  The team's activities whose attendance window is open at `now` (attendance_window?/2),
  oldest start first, for the team's Take attendance page.
  """
  def taking_attendance_now(%Team{} = team, now) do
    seconds = @attendance_window_hours * 3600
    now = DateTime.truncate(now, :second)

    Activity
    |> where([a], a.team_id == ^team.id)
    |> not_deleted()
    |> where([a], a.started_at <= ^DateTime.add(now, seconds))
    |> where([a], a.finished_at >= ^DateTime.add(now, -seconds))
    |> order_by([a], asc: a.started_at, asc: a.id)
    |> Repo.all()
  end

  @doc "The team's next activity to start after `now`, or nil."
  def next_after(%Team{} = team, now) do
    Activity
    |> where([a], a.team_id == ^team.id)
    |> not_deleted()
    |> where([a], a.started_at > ^DateTime.truncate(now, :second))
    |> order_by([a], asc: a.started_at, asc: a.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Activities that started in the last #{Service.Period.recent_days()} days and have finished by `now`.
  The dashboard counts drafts this way, and the activity list's "Last 30 days" shows
  the same rows, so the count and the list agree.
  """
  def finished_recently(query, now) do
    since = now |> DateTime.add(-Service.Period.recent_days(), :day) |> DateTime.truncate(:second)
    now = DateTime.truncate(now, :second)

    query
    |> where([r], r.started_at >= ^since)
    |> where([r], r.finished_at <= ^now)
  end

  @doc "Rows that started in `year` in `timezone`."
  def started_in(query, year, timezone) do
    {start, finish} = Service.YearRange.bounds(year, timezone)

    query
    |> where([r], r.started_at >= ^start)
    |> where([r], r.started_at < ^finish)
  end

  @doc """
  Activities with none of the hours tags (#323): no primary, secondary, or other tag.
  `hours_tags` is hours_tags/1.
  """
  def without_hours_tag(query, hours_tags) do
    titles = hours_tags |> Map.values() |> Enum.reject(&is_nil/1) |> Jason.encode!()

    where(
      query,
      [r],
      fragment(
        "NOT EXISTS (SELECT 1 FROM json_each(?) j WHERE j.value IN (SELECT value FROM json_each(?)))",
        r.tags,
        ^titles
      )
    )
  end

  @doc "Activities that carry the tag titled `title`."
  def tagged(query, title),
    do:
      where(
        query,
        [r],
        fragment("EXISTS (SELECT 1 FROM json_each(?) WHERE value = ?)", r.tags, ^title)
      )

  @doc "Rows that overlap `start` to `finish`, so a weekend course stays in while it runs."
  def overlapping(query, start, finish) do
    query
    |> where([r], r.started_at < ^finish)
    |> where([r], r.finished_at > ^start)
  end

  @doc "The years `query`'s rows span, newest first, in `timezone`."
  def years(query, timezone) do
    {first, last} =
      query
      |> select([r], {min(r.started_at), max(r.started_at)})
      |> Repo.one()

    Service.YearRange.years(first, last, timezone)
  end

  def get_by(params), do: Repo.get_by(Activity, params)

  def insert!(params) do
    changeset = Activity.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%Activity{} = record, params) do
    changeset = Activity.build_changeset(record, params)
    Repo.update!(changeset)
  end
end
