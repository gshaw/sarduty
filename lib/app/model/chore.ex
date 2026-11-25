defmodule App.Model.Chore do
  use App, :model

  alias App.Accounts.User
  alias App.Field.TrimmedString
  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  # Time a member gives the team outside activities (#341), logged on their Chores page.
  # It waits until a team admin accepts or declines it. The date is a day on the team's
  # clock, and a chore counts in the month it was done, not the month it was logged.
  schema "chores" do
    belongs_to :team, Team
    belongs_to :member, Member
    belongs_to :chore_category, ChoreCategory
    belongs_to :decided_by_user, User
    # While accepted, the D4H event of its chore category and month (App.Model.ChoreEvent).
    belongs_to :chore_event, ChoreEvent
    field :date, :date
    field :minutes, :integer
    # What the form's Time box holds, such as "2.5h". build_changeset/5 reads it into minutes.
    field :time, :string, virtual: true
    # What the member did, in their words. A team admin reads it, and so does anyone who
    # opens the D4H event.
    field :description, TrimmedString, redact: true
    field :status, Ecto.Enum, values: [:waiting, :accepted, :declined], default: :waiting
    field :decided_at, :utc_datetime_usec
    field :decline_reason, TrimmedString, redact: true
    # Chores logged at once for several people (#1102) share this UUID; nil for one logged
    # alone. Each person's chore is its own row, the same in every other way.
    field :logged_together_id, :string
    # Who logged it. Nil for chores logged before #1102, and once that member is removed.
    belongs_to :logged_by_member, Member
    # Every chore logged with it, itself included, in any status. Preload it with
    # logged_with_query/1, which keeps it to the team.
    has_many :logged_with, Chore,
      foreign_key: :logged_together_id,
      references: :logged_together_id

    timestamps(type: :utc_datetime_usec)
  end

  @window_days 60
  @max_minutes 24 * 60
  @time_blank "Enter how long it took"

  @doc "How many days back a member can log a chore."
  def window_days, do: @window_days

  @doc """
  A chore's category, description, date, and time. The form sends its time as text, read
  by Service.Convert.parse_duration/1 into minutes. `category_ids` are the ones it may have. With `today`, the
  date must not be in the future, where D4H counts the hours as signed up, not attended; a
  member's must also be within the last #{@window_days} days. A team admin passes
  `:team_admin` for any date that has passed.
  """
  def build_changeset(data, params, category_ids, today, who \\ :member) do
    data
    |> cast(params, [:chore_category_id, :description, :date])
    # A cleared Time box is a change too, so it can't keep the old minutes.
    |> cast(params, [:time], empty_values: [])
    |> validate_required([:chore_category_id], message: "Select a category")
    |> validate_required([:description], message: "Enter what you did")
    |> update_change(:description, &String.replace(&1, ~r/\s+/, " "))
    |> validate_length(:description, max: 200, message: "Keep it under 200 characters")
    |> validate_inclusion(:chore_category_id, category_ids, message: "Select a category")
    |> validate_required([:date], message: "Enter the date you did it")
    |> validate_date(today, who)
    |> put_minutes()
    |> App.Validate.in_field_order([:chore_category_id, :description, :date, :time])
  end

  # The minutes from the Time box. A chore whose time wasn't sent keeps its minutes.
  defp put_minutes(changeset) do
    case fetch_change(changeset, :time) do
      {:ok, text} ->
        put_minutes(changeset, String.trim(text || ""), Service.Convert.parse_duration(text))

      :error when is_nil(changeset.data.minutes) ->
        add_error(changeset, :time, @time_blank)

      :error ->
        changeset
    end
  end

  defp put_minutes(changeset, "", nil),
    do: add_error(changeset, :time, @time_blank)

  defp put_minutes(changeset, _text, nil),
    do: add_error(changeset, :time, "Enter the time like 45m, 2h, or 2.5h")

  defp put_minutes(changeset, _text, 0), do: add_error(changeset, :time, "Enter a time over 0")

  defp put_minutes(changeset, _text, minutes) when minutes > @max_minutes,
    do: add_error(changeset, :time, "Enter up to 24h")

  defp put_minutes(changeset, _text, minutes), do: put_change(changeset, :minutes, minutes)

  defp validate_date(changeset, nil, _who), do: changeset

  defp validate_date(changeset, today, who) do
    date = get_field(changeset, :date)

    cond do
      is_nil(date) ->
        changeset

      Date.after?(date, today) ->
        add_error(changeset, :date, "Enter a date that has passed")

      who == :member and Date.diff(today, date) > @window_days ->
        add_error(changeset, :date, window_message())

      true ->
        changeset
    end
  end

  defp window_message,
    do: "Enter a date in the last #{Service.Format.days(@window_days)}"

  @doc "A team admin's answer: accepted, or declined with a reason the member sees."
  def decide_changeset(%Chore{} = chore, status, user, now, reason \\ nil) do
    chore
    |> cast(%{decline_reason: reason}, [:decline_reason])
    |> change(status: status, decided_by_user_id: user.id, decided_at: now)
    |> then(&if status == :declined, do: validate_reason(&1), else: &1)
  end

  defp validate_reason(changeset) do
    changeset
    |> validate_required([:decline_reason], message: "Enter why, for the member")
    |> validate_length(:decline_reason, max: 300, message: "Keep it under 300 characters")
  end

  @doc """
  Whether it's `member`'s own, which another team admin should accept (#697): theirs, or
  logged together with one of theirs that still exists, in any status (#1102). Logging
  chores for others doesn't make them yours. Nil, a user who isn't one of the team's
  members, has none. Reads the preloaded `logged_with` of a chore logged together.
  """
  def own?(%Chore{member_id: member_id}, %Member{id: member_id}), do: true
  def own?(%Chore{logged_together_id: nil}, _member), do: false

  def own?(%Chore{logged_with: logged_with}, %Member{id: member_id}) when is_list(logged_with),
    do: Enum.any?(logged_with, &(&1.member_id == member_id))

  def own?(%Chore{}, nil), do: false

  @doc "The chores logged with it, in any status, not counting itself: [] for one logged alone."
  def others(%Chore{logged_together_id: nil}), do: []

  def others(%Chore{id: id, logged_with: logged_with}),
    do: Enum.reject(logged_with, &(&1.id == id))

  @doc """
  The query `logged_with` preloads through, kept to the team, with each chore's member,
  A to Z.
  """
  def logged_with_query(team_id) do
    from c in Chore,
      join: m in assoc(c, :member),
      where: c.team_id == ^team_id,
      order_by: [asc: m.name, asc: c.id],
      preload: [member: m]
  end

  @doc """
  Whether a team admin can delete their own declined chore (#1102): not while a chore
  logged with it waits, since deleting it would end Accept my own chores for the rest.
  """
  def team_admin_can_delete?(%Chore{status: :declined} = chore),
    do: chore |> others() |> Enum.all?(&(&1.status != :waiting))

  def team_admin_can_delete?(%Chore{}), do: false

  @doc "Whether the member can change or delete it: only while it waits."
  def member_can_change?(%Chore{status: status}), do: status == :waiting

  @doc "Whether the member can delete it: while it waits, or once declined."
  def member_can_delete?(%Chore{status: status}), do: status in [:waiting, :declined]

  @doc """
  A member's chores, newest first, with their categories. `status:` keeps one status,
  and `limit:` the latest few.
  """
  def get_all_for_member(%Member{} = member, opts \\ []) do
    Chore
    |> where([c], c.team_id == ^member.team_id and c.member_id == ^member.id)
    |> filter_status(opts[:status])
    |> order_by([c], desc: c.date, desc: c.id)
    |> take(opts[:limit])
    |> preload([:chore_category, :decided_by_user, :logged_by_member])
    |> preload(logged_with: ^logged_with_query(member.team_id))
    |> Repo.all()
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: where(query, [c], c.status == ^status)

  defp take(query, nil), do: query
  defp take(query, count), do: limit(query, ^count)

  @doc """
  The team's chores in `status`, with their members and categories: waiting ones oldest
  first, to accept in turn, and the rest newest first.
  """
  def get_all_for_team(team_id, status) do
    Chore
    |> where([c], c.team_id == ^team_id and c.status == ^status)
    |> order_by_status(status)
    |> preload([:member, :chore_category])
    |> preload(logged_with: ^logged_with_query(team_id))
    |> Repo.all()
  end

  defp order_by_status(query, :waiting), do: order_by(query, [c], asc: c.date, asc: c.id)
  defp order_by_status(query, _status), do: order_by(query, [c], desc: c.date, desc: c.id)

  @doc "How many of the team's chores are in each status, with every status there."
  def count_by_status(team_id) do
    counts =
      Chore
      |> where([c], c.team_id == ^team_id)
      |> group_by([c], c.status)
      |> select([c], {c.status, count(c.id)})
      |> Repo.all()
      |> Map.new()

    Map.merge(%{waiting: 0, accepted: 0, declined: 0}, counts)
  end

  @doc """
  How many of the team's waiting chores ask for `member`, a team admin: all but their
  own, which another team admin should accept (#697). With no other team admin, their
  own count too, since nobody else will accept them. A nil member, a SAR Duty admin who
  isn't on the team, has none of their own.
  """
  def count_to_accept(%Team{} = team, member, now) do
    Chore
    |> where([c], c.team_id == ^team.id and c.status == :waiting)
    |> without_own(member, Member.other_managers?(team, member, now))
    |> Repo.aggregate(:count)
  end

  defp without_own(query, %Member{id: id, team_id: team_id}, true) do
    together =
      from c in Chore,
        where: c.team_id == ^team_id and c.member_id == ^id and not is_nil(c.logged_together_id),
        select: c.logged_together_id

    where(
      query,
      [c],
      c.member_id != ^id and
        (is_nil(c.logged_together_id) or c.logged_together_id not in subquery(together))
    )
  end

  defp without_own(query, _member, _other_managers?), do: query

  @doc "How many chores each of the team's categories has in `year`, as category id to count."
  def count_by_category(team_id, year) do
    {first, last} = {Date.new!(year, 1, 1), Date.new!(year, 12, 31)}

    Chore
    |> where([c], c.team_id == ^team_id and c.date >= ^first and c.date <= ^last)
    |> where([c], c.status != :declined)
    |> group_by([c], c.chore_category_id)
    |> select([c], {c.chore_category_id, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  One of the team's chores, with its member, category, event, who decided it, who logged
  it, and the chores logged with it.
  """
  def find!(%Team{} = team, id) do
    Chore
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload([:member, :chore_category, :chore_event, :decided_by_user])
    |> Repo.preload([:logged_by_member, logged_with: logged_with_query(team.id)])
  end

  @doc "One of the member's own chores."
  def find_for_member!(%Member{} = member, id) do
    Chore
    |> Repo.get_by!(id: id, team_id: member.team_id, member_id: member.id)
    |> Repo.preload([:chore_category, :decided_by_user])
    |> Repo.preload(logged_with: logged_with_query(member.team_id))
  end
end
