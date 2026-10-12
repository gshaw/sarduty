defmodule App.Model.Activity do
  use App, :model

  import Ecto.Query

  alias App.Field.TrimmedString
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Repo

  @default_hours_tags %{primary: "Primary Hours", secondary: "Secondary Hours"}

  @doc """
  The D4H tags that make an activity count as primary or secondary hours, as
  `%{primary: tag, secondary: tag}`. A team's organization may name its own (#289);
  otherwise "Primary Hours" and "Secondary Hours". Uses the team's organization when it
  is preloaded, and reads just its tags when it isn't.
  """
  def hours_tags(%Organization{} = organization) do
    %{
      primary: organization.primary_hours_tag || @default_hours_tags.primary,
      secondary: organization.secondary_hours_tag || @default_hours_tags.secondary
    }
  end

  def hours_tags(%Team{organization: %Organization{} = organization}),
    do: hours_tags(organization)

  def hours_tags(%Team{organization_id: nil}), do: @default_hours_tags

  def hours_tags(%Team{organization_id: organization_id}) do
    Organization
    |> where([o], o.id == ^organization_id)
    |> select([o], %Organization{
      primary_hours_tag: o.primary_hours_tag,
      secondary_hours_tag: o.secondary_hours_tag
    })
    |> Repo.one!()
    |> hours_tags()
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
    # for their attendance links and scans, and left out of every list.
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
  end

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

  @recent_days 30

  def recent_days, do: @recent_days

  @doc """
  Activities that started in the last #{@recent_days} days and have finished by `now`.
  The dashboard counts drafts this way, and the activity list's "Last 30 days" shows
  the same rows, so the count and the list agree.
  """
  def finished_recently(query, now) do
    since = now |> DateTime.add(-@recent_days, :day) |> DateTime.truncate(:second)
    now = DateTime.truncate(now, :second)

    query
    |> where([r], r.started_at >= type(^DateTime.to_naive(since), :naive_datetime))
    |> where([r], r.finished_at <= type(^DateTime.to_naive(now), :naive_datetime))
  end

  @doc "Rows that started in `year` in `timezone`."
  def started_in(query, year, timezone) do
    {start, finish} = Service.YearRange.bounds(year, timezone)

    query
    |> where([r], r.started_at >= type(^start, :naive_datetime))
    |> where([r], r.started_at < type(^finish, :naive_datetime))
  end

  @doc "Rows that overlap `start` to `finish`, so a weekend course stays in while it runs."
  def overlapping(query, start, finish) do
    query
    |> where([r], r.started_at < type(^finish, :naive_datetime))
    |> where([r], r.finished_at > type(^start, :naive_datetime))
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
