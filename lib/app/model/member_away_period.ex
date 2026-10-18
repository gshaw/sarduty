defmodule App.Model.MemberAwayPeriod do
  use App, :model

  alias App.Accounts.User
  alias App.Field.TrimmedString
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.Team
  alias App.Repo

  # A dated time a member is away, such as leave (#366). SAR Duty's own data: nothing
  # here goes to D4H. Days are on the team's clock, and `ends_on` is the last day away.
  schema "member_away_periods" do
    belongs_to :team, Team
    belongs_to :member, Member
    belongs_to :created_by_user, User
    field :starts_on, :date
    field :ends_on, :date
    # A few words a team admin writes, such as "Parental leave". Personal, so redacted.
    field :reason, TrimmedString, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [:starts_on, :ends_on, :reason])
    |> validate_required([:starts_on], message: "Enter the first day away.")
    |> validate_required([:ends_on], message: "Enter the last day away.")
    |> validate_required([:reason], message: "Enter a reason, such as Parental leave.")
    |> validate_length(:reason, max: 60, message: "Keep the reason under 60 characters.")
    |> validate_ends_on_or_after_starts()
    |> App.Validate.in_field_order([:starts_on, :ends_on, :reason])
  end

  defp validate_ends_on_or_after_starts(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.before?(ends_on, starts_on),
      do: add_error(changeset, :ends_on, "Enter a last day on or after the first."),
      else: changeset
  end

  @doc "Whether `today` falls in the period."
  def current?(%MemberAwayPeriod{} = period, %Date{} = today),
    do: not Date.after?(period.starts_on, today) and not Date.before?(period.ends_on, today)

  @doc """
  The member's standing on `today` (#366): `:not_a_person`, `{:away, period}` for the
  current away period that ends last, or `:active`. Not a person wins over an away
  period. Active is never stored: it is the absence of the other two.
  """
  def standing(%{not_a_person: true}, _periods, _today), do: :not_a_person

  def standing(_member, periods, %Date{} = today) do
    case periods
         |> Enum.filter(&current?(&1, today))
         |> Enum.max_by(& &1.ends_on, Date, fn -> nil end) do
      nil -> :active
      period -> {:away, period}
    end
  end

  @doc """
  The day an early end makes the last day away: yesterday, so the member is active from
  today. Only a period that started before today and hasn't ended can end early; delete
  one that hasn't started.
  """
  def early_end(%MemberAwayPeriod{} = period, %Date{} = today) do
    yesterday = Date.add(today, -1)

    if current?(period, today) and Date.before?(period.starts_on, today),
      do: {:ok, yesterday},
      else: :error
  end

  @doc "The member's away periods, latest first."
  def for_member(%Member{} = member) do
    MemberAwayPeriod
    |> where([p], p.team_id == ^member.team_id and p.member_id == ^member.id)
    |> order_by([p], desc: p.starts_on, desc: p.id)
    |> Repo.all()
  end

  @doc "The member's standing today in the team's time zone."
  def standing_today(%Member{} = member, timezone, now \\ DateTime.utc_now()),
    do: standing(member, for_member(member), Service.Period.today(now, timezone))

  def find!(%Team{} = team, id), do: Repo.get_by!(MemberAwayPeriod, id: id, team_id: team.id)
end
