defmodule App.Model.Member do
  use App, :model

  alias App.Model.Attendance
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCheckIn
  alias App.Model.MemberQualificationAward
  alias App.Model.Standing
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Repo

  schema "members" do
    belongs_to :team, Team
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
    # Maps with "name", "relation", "primary_phone", "secondary_phone" (#423). Only team
    # admins and the member see them.
    field :primary_emergency_contact, :map, redact: true
    field :secondary_emergency_contact, :map, redact: true
    field :position, :string
    field :joined_at, :utc_datetime
    field :left_at, :utc_datetime
    # D4H's access level: 0 OWNER, 1 EDITOR, 2 MEMBER, 3 MEMBER_PLUS, 4 NO_ACCESS.
    field :d4h_permission, :integer
    field :d4h_status, :string
    # Values of the member fields the team copies (#681), by D4H field id: see
    # App.Model.CustomField. Nil until copied.
    field :custom_values, :map, redact: true
    # Set by a team admin in SAR Duty, never from D4H, so build_changeset/2 leaves it out.
    field :not_a_person, :boolean, default: false
    # Whether team admins can email reminders to reply (#444). Set by the member in SAR
    # Duty, never from D4H, so build_changeset/2 leaves it out too.
    field :invitation_reminders, :boolean, default: true
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%Member{}, params)

  # Rows are copies of D4H, so they take whatever D4H holds: no length or format
  # rules. A refresh that rejects one row fails for the whole team. D4H allows a member
  # with no start date, so `joined_at` may be empty (#421).
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
      :primary_emergency_contact,
      :secondary_emergency_contact,
      :position,
      :joined_at,
      :left_at,
      :d4h_permission,
      :d4h_status,
      :custom_values
    ])
    |> unique_constraint([:team_id, :d4h_member_id])
    |> validate_required([:team_id, :d4h_member_id, :name])
  end

  def scope(q, team_id: team_id), do: where(q, team_id: ^team_id)

  def get_all(team_id) do
    Member
    |> where([r], r.team_id == ^team_id)
    |> order_by([r], asc: r.name)
    |> Repo.all()
  end

  @doc """
  The roles the team's members hold, most held first, for the Role box's suggestions. A
  role is D4H's free-text position, so these steer admins to the team's own words.
  """
  def roles(%Team{} = team) do
    Member
    |> where([m], m.team_id == ^team.id and fragment("trim(?) != ''", m.position))
    |> group_by([m], fragment("trim(?)", m.position))
    |> order_by([m], desc: count(m.id), asc: fragment("trim(?)", m.position))
    |> select([m], fragment("trim(?)", m.position))
    |> Repo.all()
  end

  @doc "The first word of the member's name, for a line that speaks of them."
  def first_name(%{name: name}), do: name |> String.split(" ", parts: 2) |> hd()

  @doc """
  What the member lacks that login, emailed letters, tax credit letters, and the mileage
  report need, in the order the members page shows it: `:mobile_phone`, `:email`,
  `:address` (#213).
  """
  def missing_details(%{} = member) do
    Enum.filter(
      [
        blank?(member.phone) && :mobile_phone,
        blank?(member.email) && :email,
        blank?(member.address) && :address
      ],
      & &1
    )
  end

  defp blank?(value), do: value in [nil, ""]

  @doc "Narrows `query` to members `missing_details/1` finds something for."
  def missing_details_query(query) do
    where(
      query,
      [m],
      is_nil(m.phone) or m.phone == "" or is_nil(m.email) or m.email == "" or
        is_nil(m.address) or m.address == ""
    )
  end

  # The one test of who is on the team, as a query and as current?/2: no leave date by
  # `now`, and not Retired in D4H. Anyone else is retired: SAR Duty's word for a member
  # D4H retired or stopped listing, whichever field says so.

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
  Narrows `query` to people, leaving out members a team admin marked not a person. Most
  queries want counted_query/1, which leaves out retiring members too.
  """
  def people_query(query), do: where(query, [m], not m.not_a_person)

  @doc """
  Narrows `query` to the members SAR Duty counts (#514): people_query/1, and not in their
  team's Retiring group. A retiring member is no longer a member, so the Dashboard's
  counts, Missing details, Add members, Take attendance, and organization totals read
  this. Logins don't: not a person changes counts and pickers, never access.
  """
  def counted_query(query), do: where(query, ^counted_dynamic())

  @doc "counted_query/1's condition, on the query's first binding, for Reports' `counted` (#768)."
  def counted_dynamic,
    do:
      dynamic([m], not m.not_a_person and m.id not in subquery(Standing.all_retiring_ids_query()))

  @doc "Pure. counted_query/1 for one current member, given the team's retiring ids."
  def counted?(%Member{} = member, retiring_ids),
    do: not member.not_a_person and not MapSet.member?(retiring_ids, member.id)

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
    |> where([m], m.team_id == ^team.id and (is_nil(m.joined_at) or m.joined_at < ^since))
    |> not_in(seen_since(team, since, now))
    |> not_in(back_since(team, since_on, today))
    |> not_in(checked_in_since(team, since_on))
  end

  defp not_in(query, member_ids), do: where(query, [m], m.id not in subquery(member_ids))

  # Away periods and check-ins are days on the team's clock.
  defp clock_bounds(team, days, now) do
    since = DateTime.add(now, -days, :day)

    {DateTime.truncate(since, :second), Service.Period.today(since, team.timezone),
     Service.Period.today(now, team.timezone)}
  end

  defp seen_since(team, since, now) do
    now
    |> Attendance.attended()
    |> where([at, activity: a], a.team_id == ^team.id and at.started_at >= ^since)
    |> select([at], at.member_id)
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
  `nil` when there's none of them: a member with no joined date who has never attended.
  """
  def clock_start(row, timezone) do
    local = &(&1 |> DateTime.shift_zone!(timezone) |> DateTime.to_date())

    [
      {:attended, row.last_attended_at && local.(row.last_attended_at)},
      {:checked_in, row.checked_in_on},
      {:back, row.away_ends_on && Date.add(row.away_ends_on, 1)},
      {:joined, row.member.joined_at && local.(row.member.joined_at)}
    ]
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Enum.max_by(&elem(&1, 1), Date, fn -> nil end)
  end

  @doc """
  Each of the team's members' last activity (#367), as rows of `member_id` and
  `last_attended_at`: the latest start of a row they attended by `now`, any kind.
  Members who never attended have no row.
  """
  def last_attended_query(%Team{} = team, now) do
    now
    |> Attendance.attended()
    |> where([activity: a], a.team_id == ^team.id)
    |> group_by([at], at.member_id)
    |> select([at], %{member_id: at.member_id, last_attended_at: max(at.started_at)})
  end

  @doc "When the member last attended an activity, or nil: last_attended_query/2 for one."
  def last_attended_at(%Member{} = member, now \\ DateTime.utc_now()) do
    query =
      from row in subquery(last_attended_query(%Team{id: member.team_id}, now)),
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
    do: blank?(member.phone) and blank?(member.email) and not attended?

  @doc "Whether the member attended any activity by `now`."
  def attended?(%Member{id: id}, now \\ DateTime.utc_now()) do
    now
    |> Attendance.attended()
    |> where([a], a.member_id == ^id)
    |> Repo.exists?()
  end

  @manager_permissions [0, 1]
  @no_access 4

  @doc """
  Whether D4H makes this member one of the team's managers (#57): an OWNER or EDITOR who
  is a current member. Operational status doesn't matter.
  """
  def manager?(%Member{} = member, now),
    do: member.d4h_permission in @manager_permissions and current?(member, now)

  @doc """
  The members this email logs in as (#156): one per team with member logins on, where a
  current member with this email isn't retiring. A member marked not a person, such as a
  sign-in kiosk, logs in like any member. A team where two such
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
    |> not_retiring_query()
    |> preload([m, t], team: t)
  end

  @doc """
  Narrows `query` to members not in their team's Retiring group (#514), on any team. Read
  through counted_query/1: someone on their way out loses access on their next page once
  a team admin marks them retiring, not weeks later when D4H retires them.
  """
  def not_retiring_query(query),
    do: where(query, [m], m.id not in subquery(Standing.all_retiring_ids_query()))

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
  Narrows `query` to members who can log in to D4H, `true`, or who can't, `false`: a
  known permission other than No access. A member whose permission D4H didn't send is
  in neither.
  """
  def d4h_access_query(query, true),
    do: where(query, [m], not is_nil(m.d4h_permission) and m.d4h_permission != @no_access)

  def d4h_access_query(query, false), do: where(query, [m], m.d4h_permission == @no_access)

  @doc "Pure. d4h_access_query/2's `true` for one member."
  def d4h_access?(%{d4h_permission: permission}),
    do: not is_nil(permission) and permission != @no_access

  @doc """
  Narrows `query` to the members who log in as their team's team admins: the one bar for
  logins (Team.get_managed_by/2), Team admins, and an organization's team admin emails.
  A D4H Owner or Editor, current on `now`, and not retiring. A member marked not a person
  is in: D4H gave it the access, and the Team admins page shows it with its badge.
  """
  def managers_query(query, now) do
    query
    |> where([m], m.d4h_permission in @manager_permissions)
    |> current_query(now)
    |> not_retiring_query()
  end

  @doc """
  Whether the team has a manager (managers_query/2) besides `member`, who can accept what
  `member` sent: their own chores and certificates (#697). False for nil, a SAR Duty admin
  who isn't on the team.
  """
  def other_managers?(_team, nil, _now), do: false

  def other_managers?(%Team{} = team, %Member{} = member, now) do
    Member
    |> where([m], m.team_id == ^team.id and m.id != ^member.id)
    |> managers_query(now)
    |> Repo.exists?()
  end

  @doc """
  The team's contacts (#780), first then second: the members a team admin picked, while
  they are current, not retiring, and have an email. One who leaves drops off, so the
  team is asked to pick again. `[]` for none.
  """
  def get_team_contacts(%Team{} = team, now) do
    ids = [team.first_contact_id, team.second_contact_id] |> Enum.reject(&is_nil/1) |> Enum.uniq()
    found = team |> team_contacts_query(ids) |> current_query(now) |> Repo.all()
    Enum.flat_map(ids, fn id -> Enum.filter(found, &(&1.id == id)) end)
  end

  defp team_contacts_query(team, ids) do
    Member
    |> where([m], m.team_id == ^team.id and m.id in ^ids)
    |> where([m], not is_nil(m.email) and m.email != "")
    |> not_retiring_query()
  end

  @doc "The team's managers (managers_query/2), by name."
  def get_managers(%Team{} = team, now) do
    Member
    |> where([m], m.team_id == ^team.id)
    |> managers_query(now)
    |> order_by([m], asc: m.name)
    |> Repo.all()
  end

  @doc """
  Who a login is on the team, for "sent by" lines: their member name, or their email when
  no current member has it. Nil for no user.
  """
  def name_for_user(%Team{} = _team, nil, _now), do: nil

  def name_for_user(%Team{} = team, user, now) do
    case find_by_email(team, user.email, now) do
      %Member{name: name} -> name
      nil -> user.email
    end
  end

  @doc """
  The team's current member with this email, or nil when there is none or two share it.
  A team admin replies to invitations as this member (#444), on a team with member
  logins off too.
  """
  def find_by_email(%Team{} = team, email, now) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    members =
      Member
      |> where([m], m.team_id == ^team.id and fragment("lower(?)", m.email) == ^email)
      |> current_query(now)
      |> people_query()
      |> Repo.all()

    case members do
      [member] -> member
      _none_or_shared -> nil
    end
  end

  def find!(team, id), do: Repo.get_by!(Member, id: id, team_id: team.id)

  @doc "The team's member with this id, or nil."
  def find(team, id), do: Repo.get_by(Member, id: id, team_id: team.id)

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
