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
    # The D4H event a team admin sent it on (App.Operation.SendChores); nil until then.
    belongs_to :chore_event, ChoreEvent
    field :date, :date
    field :minutes, :integer
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

  @doc "How many days back a member can log a chore."
  def window_days, do: @window_days

  @doc """
  A chore's date, minutes, chore category, and description. `category_ids` are the ones
  it may have. With `today`, the date must be within the last #{@window_days} days and
  not in the future, as for a member; a team admin passes nil for any date.
  """
  def build_changeset(data, params, category_ids, today) do
    data
    |> cast(params, [:date, :minutes, :chore_category_id, :description])
    |> validate_required([:date], message: "Enter the date you did it")
    |> validate_required([:minutes], message: "Enter how many minutes it took")
    |> validate_required([:chore_category_id], message: "Select a category")
    |> validate_required([:description], message: "Enter what you did")
    |> validate_number(:minutes,
      greater_than: 0,
      less_than_or_equal_to: @max_minutes,
      message: "Enter minutes from 1 to #{@max_minutes}"
    )
    |> validate_inclusion(:chore_category_id, category_ids, message: "Select a category")
    |> validate_length(:description, max: 200, message: "Keep it under 200 characters")
    |> validate_window(today)
    |> App.Validate.in_field_order([:date, :minutes, :chore_category_id, :description])
  end

  defp validate_window(changeset, nil), do: changeset

  defp validate_window(changeset, today) do
    date = get_field(changeset, :date)

    cond do
      is_nil(date) -> changeset
      Date.after?(date, today) -> add_error(changeset, :date, "Enter a date that has passed")
      Date.diff(today, date) > @window_days -> add_error(changeset, :date, window_message())
      true -> changeset
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

  @doc "Whether the member can change or delete it: only while it waits."
  def member_can_change?(%Chore{status: status}), do: status == :waiting

  @doc "Whether it is on an event D4H has approved, so SAR Duty cannot change it."
  def locked?(%Chore{chore_event_id: nil}), do: false

  def locked?(%Chore{chore_event_id: id}),
    do: ChoreEvent |> where([e], e.id == ^id and e.locked) |> Repo.exists?()

  @doc "Whether the member can delete it: while it waits, or once declined."
  def member_can_delete?(%Chore{status: status}), do: status in [:waiting, :declined]

  @doc "A member's chores, newest first, with their categories."
  def get_all_for_member(%Member{} = member) do
    Chore
    |> where([c], c.team_id == ^member.team_id and c.member_id == ^member.id)
    |> order_by([c], desc: c.date, desc: c.id)
    |> preload([:chore_category, :decided_by_user])
    |> Repo.all()
  end

  @doc "The team's waiting chores, oldest first, with their members and categories."
  def get_waiting(team_id) do
    Chore
    |> where([c], c.team_id == ^team_id and c.status == :waiting)
    |> order_by([c], asc: c.date, asc: c.id)
    |> preload([:member, :chore_category])
    |> Repo.all()
  end

  @doc "The team's accepted chores not sent yet, oldest first, with members and categories."
  def get_ready(team_id) do
    Chore
    |> where([c], c.team_id == ^team_id and c.status == :accepted and is_nil(c.chore_event_id))
    |> order_by([c], asc: c.date, asc: c.id)
    |> preload([:member, :chore_category])
    |> Repo.all()
  end

  @doc "How many of the team's accepted chores are not sent yet."
  def count_ready(team_id) do
    Chore
    |> where([c], c.team_id == ^team_id and c.status == :accepted and is_nil(c.chore_event_id))
    |> Repo.aggregate(:count)
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

  @doc "One of the team's chores, with its member, category, and who decided it."
  def find!(%Team{} = team, id) do
    Chore
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload([:member, :chore_category, :decided_by_user])
  end

  @doc "One of the member's own chores."
  def find_for_member!(%Member{} = member, id) do
    Chore
    |> Repo.get_by!(id: id, team_id: member.team_id, member_id: member.id)
    |> Repo.preload([:chore_category, :decided_by_user])
  end
end
