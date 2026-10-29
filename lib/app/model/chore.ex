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
    timestamps(type: :utc_datetime_usec)
  end

  @window_days 60
  @max_minutes 24 * 60
  @time_blank "Enter how long it took"

  @doc "How many days back a member can log a chore."
  def window_days, do: @window_days

  @doc """
  A chore's category, description, date, and time. The form sends its time as text, read
  by parse_time/1 into minutes. `category_ids` are the ones it may have. With `today`, the
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
      {:ok, text} -> put_minutes(changeset, String.trim(text || ""), parse_time(text))
      :error when is_nil(changeset.data.minutes) -> add_error(changeset, :time, @time_blank)
      :error -> changeset
    end
  end

  defp put_minutes(changeset, "", nil),
    do: add_error(changeset, :time, @time_blank)

  defp put_minutes(changeset, _text, nil),
    do: add_error(changeset, :time, "Enter the time like 45m, 2h, or 2.5h")

  defp put_minutes(changeset, _text, 0), do: add_error(changeset, :time, "Enter a time over 0")

  # "30" reads as 30 hours, so it asks whether they meant minutes.
  defp put_minutes(changeset, text, minutes) when minutes > @max_minutes do
    message =
      if Regex.match?(~r/^\d+$/, text),
        do: "Enter #{text}m for minutes, or up to 24h",
        else: "Enter up to 24h"

    add_error(changeset, :time, message)
  end

  defp put_minutes(changeset, _text, minutes), do: put_change(changeset, :minutes, minutes)

  @doc """
  Minutes from what someone types for a chore's time: "45m", "2h", "2.5h", "1h 30m", or
  "1:30". A bare number is hours, since most chores take an hour or more. Nil when it is
  none of these.
  """
  def parse_time(text) when is_binary(text) do
    squeezed = text |> String.downcase() |> String.replace(~r/\s+/, "")

    Enum.find_value(time_formats(), fn {regex, kind} ->
      if parts = Regex.run(regex, squeezed, capture: :all_but_first),
        do: to_minutes(kind, parts)
    end)
  end

  def parse_time(_text), do: nil

  # h, hr, hrs, hour, hours; m, min, mins, minute, minutes.
  defp time_formats do
    [
      {~r/^(\d+(?:\.\d+)?|\.\d+)(?:h|hrs?|hours?)?$/, :hours},
      {~r/^(\d+)(?:m|mins?|minutes?)$/, :minutes},
      {~r/^(\d+)(?:h|hrs?|hours?)(\d+)(?:m|mins?|minutes?)?$/, :hours_minutes},
      {~r/^(\d+):([0-5]\d)$/, :hours_minutes}
    ]
  end

  defp to_minutes(:hours, [hours]), do: round(decimal(hours) * 60)
  defp to_minutes(:minutes, [minutes]), do: String.to_integer(minutes)

  defp to_minutes(:hours_minutes, [hours, minutes]),
    do: String.to_integer(hours) * 60 + String.to_integer(minutes)

  defp decimal("." <> _rest = number), do: decimal("0" <> number)
  defp decimal(number), do: number |> Float.parse() |> elem(0)

  @doc "A chore's minutes as the Time box shows them, for parse_time/1 to read back: \"1h 30m\"."
  def time_text(nil), do: nil
  def time_text(minutes) when minutes < 60, do: "#{minutes}m"
  def time_text(minutes) when rem(minutes, 60) == 0, do: "#{div(minutes, 60)}h"
  def time_text(minutes), do: "#{div(minutes, 60)}h #{rem(minutes, 60)}m"

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
  Whether `member` logged it: a team admin's own chore, which another team admin should
  accept (#697). Nil, a user who isn't one of the team's members, has none.
  """
  def own?(%Chore{member_id: member_id}, %Member{id: member_id}), do: true
  def own?(%Chore{}, _member), do: false

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
    |> preload([:chore_category, :decided_by_user])
    |> Repo.all()
  end

  @doc "The category of the member's most recently logged chore, or nil if they have none."
  def last_category_id(%Member{} = member) do
    Chore
    |> where([c], c.team_id == ^member.team_id and c.member_id == ^member.id)
    |> order_by([c], desc: c.id)
    |> limit(1)
    |> select([c], c.chore_category_id)
    |> Repo.one()
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

  @doc "How many of the team's chores wait for a team admin."
  def count_waiting(team_id) do
    Chore
    |> where([c], c.team_id == ^team_id and c.status == :waiting)
    |> Repo.aggregate(:count)
  end

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

  @doc "One of the team's chores, with its member, category, event, and who decided it."
  def find!(%Team{} = team, id) do
    Chore
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload([:member, :chore_category, :chore_event, :decided_by_user])
  end

  @doc "One of the member's own chores."
  def find_for_member!(%Member{} = member, id) do
    Chore
    |> Repo.get_by!(id: id, team_id: member.team_id, member_id: member.id)
    |> Repo.preload([:chore_category, :decided_by_user])
  end
end
