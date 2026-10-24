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
  The member's standing on `today` (#366): `:retired`, `:not_a_person`, `{:away, period}`
  for the current away period that ends last, or `:active`. Retired comes from D4H, as
  of `now` (not Member.current?/2), and wins over the rest; not a person wins over an away
  period. Active is never stored: it is the absence of the others.
  """
  def standing(member, periods, %Date{} = today, now) do
    cond do
      not Member.current?(member, now) -> :retired
      member.not_a_person -> :not_a_person
      true -> away_or_active(periods, today)
    end
  end

  defp away_or_active(periods, today) do
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

  @doc """
  Each of the team's members away on `today`, as rows of `member_id` and `away_until`,
  the last day of the current away period that ends last: the away part of `standing/4`.
  """
  def away_query(%Team{} = team, %Date{} = today) do
    from p in MemberAwayPeriod,
      where: p.team_id == ^team.id and p.starts_on <= ^today and p.ends_on >= ^today,
      group_by: p.member_id,
      select: %{member_id: p.member_id, away_until: max(p.ends_on)}
  end

  @doc "The member's away periods, latest first."
  def for_member(%Member{} = member) do
    MemberAwayPeriod
    |> where([p], p.team_id == ^member.team_id and p.member_id == ^member.id)
    |> order_by([p], desc: p.starts_on, desc: p.id)
    |> Repo.all()
  end

  @doc ~s{The standing as text: "Active", "Away until March 1, 2027 (Parental leave)", "Not a person", or "Retired".}
  def describe_standing(:active), do: "Active"
  def describe_standing(:not_a_person), do: "Not a person"
  def describe_standing(:retired), do: "Retired"

  def describe_standing({:away, period}),
    do: "Away until #{Service.Format.date_long(period.ends_on)} (#{period.reason})"

  @doc "Every away period of the team's members."
  def get_all_for_team(team_id),
    do: MemberAwayPeriod |> where([p], p.team_id == ^team_id) |> Repo.all()

  @doc """
  A standing as `team_admin?` sees it (#440). Members see Retired, which comes from D4H.
  Away periods and Not a person are team admins' own records, and away is often leave, so
  to a member everyone else is active. Every page that shows another member's standing
  passes it through here.
  """
  def visible_standing(standing, true = _team_admin?), do: standing
  def visible_standing(:retired, false), do: :retired
  def visible_standing(_standing, false), do: :active

  @doc "The member's standing today in the team's time zone."
  def standing_today(%Member{} = member, timezone, now \\ DateTime.utc_now()),
    do: standing(member, for_member(member), Service.Period.today(now, timezone), now)

  def find!(%Team{} = team, id), do: Repo.get_by!(MemberAwayPeriod, id: id, team_id: team.id)

  def find(%Team{} = team, id), do: Repo.get_by(MemberAwayPeriod, id: id, team_id: team.id)
end
