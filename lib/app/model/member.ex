defmodule App.Model.Member do
  use App, :model

  alias App.Model.Attendance
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCheckIn
  alias App.Model.MemberQualificationAward
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Repo

  schema "members" do
    belongs_to :team, Team
    has_many :attendances, Attendance, where: [status: "attending"]
    has_many :activities, through: [:attendances, :activity]
    has_many :group_members, GroupMember
    has_many :groups, through: [:group_members, :group]
    has_many :member_qualification_awards, MemberQualificationAward
    has_many :qualifications, through: [:member_qualification_awards, :qualification]
    has_many :tax_credit_letters, TaxCreditLetter
    field :d4h_member_id, :integer
    field :ref_id, :string
    field :name, :string
    field :email, :string, redact: true
    field :phone, :string, redact: true
    field :address, :string, redact: true
    field :position, :string
    field :joined_at, :utc_datetime
    field :left_at, :utc_datetime
    # D4H's access level: 0 OWNER, 1 EDITOR, 2 MEMBER, 3 MEMBER_PLUS, 4 NO_ACCESS.
    field :d4h_permission, :integer
    field :d4h_status, :string
    # Set by a team admin in SAR Duty, never from D4H, so build_changeset/2 leaves it out.
    field :not_a_person, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%Member{}, params)

  # Rows are copies of D4H, so they take whatever D4H holds: no length or format
  # rules. A refresh that rejects one row fails for the whole team.
  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :id,
      :team_id,
      :d4h_member_id,
      :ref_id,
      :name,
      :email,
      :phone,
      :address,
      :position,
      :joined_at,
      :left_at,
      :d4h_permission,
      :d4h_status
    ])
    |> unique_constraint([:team_id, :d4h_member_id])
    |> validate_required([
      :team_id,
      :d4h_member_id,
      :name,
      :joined_at
    ])
  end

  def scope(q, team_id: team_id), do: where(q, team_id: ^team_id)

  def get_all(team_id) do
    Member
    |> where([r], r.team_id == ^team_id)
    |> order_by([r], asc: r.name)
    |> Repo.all()
  end

  @doc """
  What the member lacks that login and emailed letters need, in the order the members
  page shows it: `:mobile_phone`, `:email`.
  """
  def missing_details(%{} = member) do
    Enum.filter([blank?(member.phone) && :mobile_phone, blank?(member.email) && :email], & &1)
  end

  defp blank?(value), do: value in [nil, ""]

  @doc "Narrows `query` to members `missing_details/1` finds something for."
  def missing_details_query(query) do
    where(
      query,
      [m],
      is_nil(m.phone) or m.phone == "" or is_nil(m.email) or m.email == ""
    )
  end

  # The one test of who is on the team, as a query and as current?/2: not left as of
  # `now`, and not retired in D4H. Anyone else is departed.

  @doc "Narrows `query` to current members."
  def current_query(query, now), do: where(query, ^current_dynamic(now))

  @doc """
  current_query/2's condition, for a query that ORs it with others or joins members:
  pass the binding name for a joined member.
  """
  def current_dynamic(now, binding \\ nil)

  def current_dynamic(now, nil) do
    dynamic(
      [m],
      (is_nil(m.left_at) or m.left_at > ^now) and
        (is_nil(m.d4h_status) or m.d4h_status != "RETIRED")
    )
  end

  def current_dynamic(now, binding) when is_atom(binding) do
    dynamic(
      [{^binding, m}],
      (is_nil(m.left_at) or m.left_at > ^now) and
        (is_nil(m.d4h_status) or m.d4h_status != "RETIRED")
    )
  end

  @doc "Pure. current_query/2 for one member. A map without those keys is current."
  def current?(member, now) do
    left_at = Map.get(member, :left_at)

    (is_nil(left_at) or DateTime.after?(left_at, now)) and
      Map.get(member, :d4h_status) != "RETIRED"
  end

  @doc """
  Whether any current member of the team is not active on `today` (#367): away or not a
  person. The members list shows its Standing column only then.
  """
  def any_not_active?(%Team{} = team, %Date{} = today, now) do
    away =
      from(row in subquery(MemberAwayPeriod.away_query(team, today)),
        select: row.member_id
      )

    Member
    |> where([m], m.team_id == ^team.id)
    |> current_query(now)
    |> where([m], m.not_a_person or m.id in subquery(away))
    |> Repo.exists?()
  end

  @doc "Narrows `query` to people, leaving out members a team admin marked not a person."
  def people_query(query), do: where(query, [m], not m.not_a_person)

  @doc """
  Narrows `query` to the current members of `team` whose attendance clock is older than
  `days` days as of `now` (#366). The clock counts from the latest of: their last
  activity (an attending row on an activity not deleted, any kind), the day they joined,
  the end of an away period that has started, and their latest check-in. Nothing else is
  left out here: standing and groups are filters of their own.
  """
  def not_seen_query(query, %Team{} = team, days, now) do
    {since, since_on, today} = clock_bounds(team, days, now)

    query
    |> current_query(now)
    |> where([m], m.team_id == ^team.id and m.joined_at < type(^since, :naive_datetime))
    |> not_in(seen_since(team, since))
    |> not_in(back_since(team, since_on, today))
    |> not_in(checked_in_since(team, since_on))
  end

  defp not_in(query, member_ids), do: where(query, [m], m.id not in subquery(member_ids))

  # Stored times mix `…Z` and no zone; a bound with no zone compares right against both.
  # Away periods and check-ins are days on the team's clock.
  defp clock_bounds(team, days, now) do
    since = DateTime.add(now, -days, :day)

    {since |> DateTime.truncate(:second) |> DateTime.to_naive(),
     Service.Period.today(since, team.timezone), Service.Period.today(now, team.timezone)}
  end

  defp seen_since(team, since) do
    from at in Attendance,
      join: a in assoc(at, :activity),
      where: a.team_id == ^team.id and is_nil(a.deleted_at) and at.status == "attending",
      where: a.started_at >= type(^since, :naive_datetime),
      select: at.member_id
  end

  # An away period that has started and whose day back, the day after it ends, is on or
  # after `since_on`: the same day clock_start/2 counts from.
  defp back_since(team, since_on, today) do
    last_day = Date.add(since_on, -1)

    from p in MemberAwayPeriod,
      where: p.team_id == ^team.id and p.starts_on <= ^today and p.ends_on >= ^last_day,
      select: p.member_id
  end

  defp checked_in_since(team, since_on) do
    from c in MemberCheckIn,
      where: c.team_id == ^team.id and c.checked_in_on >= ^since_on,
      select: c.member_id
  end

  @doc """
  Pure. Where a member's attendance clock starts, as `{why, date}` with `why` one of
  `:attended`, `:checked_in`, `:back`, or `:joined`: the latest of their last activity,
  latest check-in, the day after their latest away period ended, and the day they joined.
  Takes a row with `last_attended_at`, `checked_in_on`, `away_ends_on`, and `member`.
  """
  def clock_start(row, timezone) do
    local = &(&1 |> DateTime.shift_zone!(timezone) |> DateTime.to_date())

    [
      {:attended, row.last_attended_at && local.(row.last_attended_at)},
      {:checked_in, row.checked_in_on},
      {:back, row.away_ends_on && Date.add(row.away_ends_on, 1)},
      {:joined, local.(row.member.joined_at)}
    ]
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Enum.max_by(&elem(&1, 1), Date)
  end

  @doc """
  Each of the team's members' last activity (#367), as rows of `member_id` and
  `last_attended_at`: the latest start of an activity they attended, any kind, not
  deleted. Members who never attended have no row.
  """
  def last_attended_query(%Team{} = team) do
    from at in Attendance,
      join: a in assoc(at, :activity),
      where: a.team_id == ^team.id and is_nil(a.deleted_at) and at.status == "attending",
      group_by: at.member_id,
      select: %{member_id: at.member_id, last_attended_at: max(a.started_at)}
  end

  @doc "When the member last attended an activity, or nil: last_attended_query/1 for one."
  def last_attended_at(%Member{} = member) do
    query =
      from row in subquery(last_attended_query(%Team{id: member.team_id})),
        where: row.member_id == ^member.id,
        select: type(row.last_attended_at, :utc_datetime)

    Repo.one(query)
  end

  @doc """
  Whether the member looks like a bot or a shared account: no email, no mobile phone,
  and no attendance. Only a hint; a new member looks the same until their first activity.
  """
  def looks_like_not_a_person?(%Member{not_a_person: true}, _attended?), do: false

  def looks_like_not_a_person?(%Member{} = member, attended?),
    do: missing_details(member) == [:mobile_phone, :email] and not attended?

  @doc "Whether the member attended any activity."
  def attended?(%Member{id: id}) do
    Attendance
    |> where([a], a.member_id == ^id and a.status == "attending")
    |> Repo.exists?()
  end

  @manager_permissions [0, 1]

  @doc """
  Whether D4H makes this member one of the team's managers (#57): an OWNER or EDITOR who
  is a current member. Operational status doesn't matter.
  """
  def manager?(%Member{} = member, now),
    do: member.d4h_permission in @manager_permissions and current?(member, now)

  @doc """
  The members this email logs in as (#156): one per team with member logins on, where a
  current member with this email isn't marked not a person. A team where two such
  members share the email is left out, since SAR Duty can't tell whose card to show.
  With the team, by team name.
  """
  def get_logins(email, now) when is_binary(email) do
    email
    |> logins_query(now)
    |> Repo.all()
    |> Enum.group_by(& &1.team_id)
    |> Enum.flat_map(fn
      {_team_id, [member]} -> [member]
      {_team_id, _shared} -> []
    end)
    |> Enum.sort_by(& &1.team.name)
  end

  @doc "The member `email` logs in as with this id, or nil: get_logins/2 for one member."
  def get_login(email, member_id, now),
    do: email |> get_logins(now) |> Enum.find(&(&1.id == member_id))

  defp logins_query(email, now) do
    email = email |> String.trim() |> String.downcase()

    Member
    |> join(:inner, [m], t in assoc(m, :team))
    |> where([m, t], t.member_logins and fragment("lower(?)", m.email) == ^email)
    |> current_query(now)
    |> people_query()
    |> preload([m, t], team: t)
  end

  @doc """
  Whether this email is a current member on some team, whatever their permission: not
  retired and not left. The bar an admin's email must meet to log in (#141).
  """
  def current_email?(email, now) do
    email = email |> String.trim() |> String.downcase()

    Member
    |> where([m], fragment("lower(?)", m.email) == ^email)
    |> current_query(now)
    |> Repo.exists?()
  end

  @doc """
  The emails of current members with this phone number, lowercase. D4H keeps numbers as
  typed, so each is normalized here rather than matched in SQL.
  """
  def current_emails_with_phone(e164, now) do
    now
    |> current_phones_and_emails()
    |> Repo.all()
    |> Enum.filter(fn {phone, _email} -> Service.Phone.normalize(phone) == e164 end)
    |> Enum.map(fn {_phone, email} -> email |> String.trim() |> String.downcase() end)
    |> Enum.uniq()
  end

  defp current_phones_and_emails(now) do
    Member
    |> where([m], not is_nil(m.phone) and not is_nil(m.email))
    |> current_query(now)
    |> select([m], {m.phone, m.email})
  end

  def permission_label(0), do: "Owner"
  def permission_label(1), do: "Editor"
  def permission_label(2), do: "Member"
  def permission_label(3), do: "Member plus"
  def permission_label(4), do: "No access"
  def permission_label(_), do: "Unknown"

  @doc """
  The team's managers, by name. Members marked not a person are left out, and so is a
  team key from a "SAR Duty" account. A team key from a person's account leaves them in,
  since they manage the team too.
  """
  def get_managers(%Team{} = team, now) do
    key_account = if Team.key_owner_is_sar_duty?(team), do: team.d4h_access_key_member_id

    Member
    |> where([m], m.team_id == ^team.id and m.d4h_permission in @manager_permissions)
    |> people_query()
    |> order_by([m], asc: m.name)
    |> Repo.all()
    |> Enum.filter(&(manager?(&1, now) and &1.d4h_member_id != key_account))
  end

  def find!(team, id), do: Repo.get_by!(Member, id: id, team_id: team.id)
  def get_by(params), do: Repo.get_by(Member, params)

  def insert!(params) do
    changeset = Member.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%Member{} = record, params) do
    changeset = Member.build_changeset(record, params)
    Repo.update!(changeset)
  end
end
