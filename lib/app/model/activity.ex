defmodule App.Model.Activity do
  use App, :model

  import Ecto.Query

  alias App.Field.TrimmedString
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Repo

  @number_message "Enter a whole number, 1 or more."

  @default_hours_tags %{primary: "Primary Hours", secondary: "Secondary Hours", other: nil}
  @hours_kinds [:primary, :secondary, :other]

  @doc """
  Whether the activity is locked: published, so only its published flag changes. D4H
  answers 409 "Resources cannot be updated once they have been published" (#358), and
  SAR Duty Records follows it (#585).
  """
  def locked?(%{is_published: published?}), do: published? == true

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

  @doc ~s(An hours kind in a sentence: "primary hours".)
  def hours_kind_name(:primary), do: "primary hours"
  def hours_kind_name(:secondary), do: "secondary hours"
  def hours_kind_name(:other), do: "other hours"

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

  @doc """
  Whether the tags hold two or more of the hours tags (#763), so the activity counts for
  hours its other tag says it doesn't: `counts_as/2` picks one without a word.
  `with_two_hours_tags/2` is the same rule as a query.
  """
  def two_hours_tags?(tags, hours_tags) do
    tags = tags || []
    hours_tags |> hours_titles() |> Enum.count(&(&1 in tags)) >= 2
  end

  defp hours_titles(hours_tags),
    do:
      hours_tags
      |> Map.take(@hours_kinds)
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

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
    field :description, TrimmedString, redact: true
    field :address, TrimmedString, redact: true
    field :coordinate, :string
    field :activity_kind, :string
    field :hours_kind, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :tags, {:array, :string}
    # D4H custom field values by D4H field id (#681): see App.Model.CustomField. Nil
    # until the first refresh after they were added copies them.
    field :custom_values, :map, redact: true
    # Set by the refresh when D4H stops listing the activity. Deleted activities are kept
    # for their attendance scans, and left out of every list.
    field :deleted_at, :utc_datetime
    # SAR Duty's own, never D4H's: see mark_attendance_sent/2.
    field :attendance_sent_at, :utc_datetime_usec
    # SAR Duty's own too (#447): how many signed up is enough, and how many is full. Nil
    # for no number. Change activity sets them through SaveActivity.
    field :enough_at, :integer
    field :full_at, :integer
    # The members' accepted chore minutes on a chore activity (#575), nil on any other.
    # Set where it is read, from ChoreEvent.totals/1 or put_chore_minutes/1.
    field :chore_minutes, :integer, virtual: true
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  The kind SAR Duty shows: "chores" for a chore activity (#575), else D4H's kind. D4H
  holds a chore activity as an event.
  """
  def shown_kind(%{chore_minutes: minutes}) when is_integer(minutes), do: "chores"
  def shown_kind(%{activity_kind: kind}), do: kind

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
      :tags,
      :custom_values
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

  @doc """
  Whether the activity has finished by `now` and D4H still holds it as a draft: someone
  has to publish it. A coming activity is a draft until then, which needs no mark. Pure.
  """
  def finished_draft?(%{is_published: published?, finished_at: finished_at}, %DateTime{} = now),
    do: published? == false and not DateTime.after?(finished_at, now)

  @doc "Whether the activity has started by `now`. Pure."
  def started?(%{started_at: started_at}, %DateTime{} = now),
    do: not DateTime.before?(now, started_at)

  @doc """
  Whether the activity is still open by `now`: not deleted and not started. Members reply
  and team admins add members and send reminders and updates only then. Pure.
  """
  def open?(%Activity{} = activity, %DateTime{} = now),
    do: not deleted?(activity) and not started?(activity, now)

  @doc """
  How many more members the activity needs until Enough at have signed up (#447), or nil
  when it has no Enough at, has enough, or is no longer open?/2. `counts` is the counts
  map the page shows: `ActivityMembers.counts/1` or `Attendance.reply_counts/2`'s. Pure.
  """
  def more_needed(%Activity{enough_at: enough_at} = activity, %{attending: yes}, now)
      when is_integer(enough_at) do
    if open?(activity, now) and yes < enough_at, do: enough_at - yes
  end

  def more_needed(%Activity{}, _counts, _now), do: nil

  @doc "Whether Full at or more have signed up while the activity is open?/2 (#447). Pure."
  def full?(%Activity{full_at: full_at} = activity, %{attending: yes}, now)
      when is_integer(full_at),
      do: open?(activity, now) and yes >= full_at

  def full?(%Activity{}, _counts, _now), do: false

  @doc """
  Checks Enough at and Full at, on Change activity and Change template (#447): whole
  numbers of 1 or more, and a Full at no lower than Enough at. Cast them with
  `message: &number_message/2`, so a typed word or fraction says the same.
  """
  def validate_enough_and_full(changeset) do
    changeset
    |> validate_number(:enough_at, greater_than_or_equal_to: 1, message: @number_message)
    |> validate_number(:full_at, greater_than_or_equal_to: 1, message: @number_message)
    |> validate_full_at()
  end

  defp validate_full_at(changeset) do
    enough_at = get_field(changeset, :enough_at)
    full_at = get_field(changeset, :full_at)

    if is_integer(enough_at) and is_integer(full_at) and full_at < enough_at and
         changeset.errors[:enough_at] == nil,
       do:
         add_error(
           changeset,
           :full_at,
           "Enter #{enough_at} or more, since Enough at is #{enough_at}."
         ),
       else: changeset
  end

  @doc "The cast error for Enough at and Full at: `cast(…, message: &number_message/2)`."
  def number_message(field, _meta) when field in [:enough_at, :full_at], do: @number_message
  def number_message(_field, _meta), do: nil

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
  Whether a team admin can add members to the activity now (#564): `:open` before the
  start on one neither deleted nor published, `:published` for a published one, and nil
  otherwise. Read from the copy, so InviteMembers checks again when it sends.
  """
  def adding(%Activity{} = activity, team_admin?, %DateTime{} = now) do
    cond do
      !team_admin? or not open?(activity, now) ->
        nil

      activity.is_published ->
        :published

      true ->
        :open
    end
  end

  @doc """
  Records that the activity's attendance is sent as of `at`, the time of a team admin's
  review: its send went through, or it had nothing to send (SendAttendanceToD4H). Needs
  attention lists the scans after it (#475). It never moves back, so a send from an older
  review can't bring back what a newer one cleared.
  """
  def mark_attendance_sent(%Activity{} = activity, %DateTime{} = at) do
    Activity
    |> where([a], a.id == ^activity.id and a.team_id == ^activity.team_id)
    |> where([a], is_nil(a.attendance_sent_at) or a.attendance_sent_at < ^at)
    |> Repo.update_all(set: [attendance_sent_at: at])

    :ok
  end

  @doc """
  Writes Enough at and Full at, `%{enough_at: n, full_at: n}` with either nil, once the
  change set row that names them has applied (#447). The refresh never copies them, as
  D4H never has them. Answers the activity with them.
  """
  def put_enough_and_full(%Activity{} = activity, %{enough_at: enough_at, full_at: full_at}) do
    Activity
    |> where([a], a.id == ^activity.id and a.team_id == ^activity.team_id)
    |> Repo.update_all(set: [enough_at: enough_at, full_at: full_at])

    %{activity | enough_at: enough_at, full_at: full_at}
  end

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

  @coming_up_days 14
  @coming_up_count 5

  @doc """
  The team's next #{@coming_up_count} activities whose attendance window opens after `now`,
  starting within #{@coming_up_days} days, for Coming up on the team's Take attendance page.
  With taking_attendance_now/2 it covers every activity still to come.
  """
  def taking_attendance_later(%Team{} = team, now) do
    now = DateTime.truncate(now, :second)

    Activity
    |> where([a], a.team_id == ^team.id)
    |> not_deleted()
    |> where([a], a.started_at > ^DateTime.add(now, @attendance_window_hours * 3600))
    |> where([a], a.started_at <= ^DateTime.add(now, @coming_up_days, :day))
    |> order_by([a], asc: a.started_at, asc: a.id)
    |> limit(@coming_up_count)
    |> Repo.all()
  end

  @doc """
  Activities that started in the last #{Service.Period.recent_days()} days (whole days in
  `timezone`, `Service.DayRange.last/3`) and have finished by `now`. The dashboard counts
  drafts this way, and the activity list's "Last 30 days" shows the same rows, so the
  count and the list agree.
  """
  def finished_recently(query, now, timezone) do
    {since, _finish} = Service.DayRange.last(now, timezone, Service.Period.recent_days())
    now = DateTime.truncate(now, :second)

    query
    |> where([r], r.started_at >= ^since)
    |> where([r], r.finished_at <= ^now)
  end

  @doc """
  The address, pin, and start of each of the team's activities with an address that
  started between `since` and `now`, for the places the activity form suggests (#610).
  """
  def places(%Team{} = team, %DateTime{} = since, %DateTime{} = now) do
    Activity
    |> where([a], a.team_id == ^team.id)
    |> not_deleted()
    |> where([a], a.started_at >= ^DateTime.truncate(since, :second))
    |> where([a], a.started_at <= ^DateTime.truncate(now, :second))
    |> where([a], not is_nil(a.address) and a.address != "")
    |> select([a], %{address: a.address, coordinate: a.coordinate, started_at: a.started_at})
    |> Repo.all()
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
  def without_hours_tag(query, hours_tags),
    do: where(query, ^dynamic([r], ^hours_tag_count_dynamic(hours_tags) == 0))

  @doc """
  Activities with two or more of the hours tags (#763), as `two_hours_tags?/2`.
  `hours_tags` is hours_tags/1.
  """
  def with_two_hours_tags(query, hours_tags),
    do: where(query, ^dynamic([r], ^hours_tag_count_dynamic(hours_tags) >= 2))

  @doc """
  How many of the hours tags an activity has, in SQL, on the query's first binding: 0
  for without_hours_tag/2, 2 or more for with_two_hours_tags/2, and Reports'
  `hours_tag_count` (#768).
  """
  def hours_tag_count_dynamic(hours_tags) do
    titles = hours_tags |> hours_titles() |> Jason.encode!()

    dynamic(
      [r],
      fragment(
        "(SELECT COUNT(DISTINCT j.value) FROM json_each(?) j WHERE j.value IN (SELECT value FROM json_each(?)))",
        r.tags,
        ^titles
      )
    )
  end

  @doc """
  Whether a required custom field left empty is worth flagging (#681): on a draft
  incident, since D4H refuses to publish an incident with one empty. A published one got
  past D4H already, and D4H's check on exercises and events is untested. Matches
  `missing_required_fields/1`.
  """
  def flag_missing_fields?(%__MODULE__{activity_kind: kind, is_published: published?}),
    do: kind == "incident" and !published?

  @doc """
  Draft incidents with a required D4H custom field left empty (#681), as
  `flag_missing_fields?/1`. One whose values aren't copied yet is left out: nil isn't
  known to be missing anything.
  """
  def missing_required_fields(query) do
    where(
      query,
      [r],
      r.activity_kind == "incident" and r.is_published == false and
        not is_nil(r.custom_values) and
        fragment(
          """
          EXISTS (SELECT 1 FROM custom_fields f
          WHERE f.team_id = ? AND f.target = ? AND f.required AND f.archived_at IS NULL
          AND json_extract(?, '$."' || f.d4h_custom_field_id || '"') IS NULL)
          """,
          r.team_id,
          r.activity_kind,
          r.custom_values
        )
    )
  end

  @doc """
  How long an activity ran, in whole minutes, for a query joined to
  `ChoreEvent.totals/1` as `:chores`: a chore activity lasts no time, so it's its members'
  chores (#575). Activities' Duration sort, and a report's `duration`.
  """
  def duration_dynamic do
    dynamic(
      [r, chores: c],
      fragment(
        "CAST(ROUND(COALESCE(?, (JULIANDAY(?) - JULIANDAY(?)) * 1440.0)) AS INTEGER)",
        c.minutes,
        r.finished_at,
        r.started_at
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
