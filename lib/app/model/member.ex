defmodule App.Model.Member do
  use App, :model

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Repo
  alias App.Validate

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
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%Member{}, params)

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
    |> Validate.name(:name)
    |> Validate.address(:address)
    |> Validate.email(:email)
  end

  def scope(q, team_id: team_id), do: where(q, team_id: ^team_id)

  def get_all(team_id) do
    Member
    |> where([r], r.team_id == ^team_id)
    |> order_by([r], asc: r.name)
    |> Repo.all()
  end

  # D4H sets endsAt when a member retires. Takes any map with left_at.
  def current?(%{left_at: left_at}, now), do: is_nil(left_at) or DateTime.after?(left_at, now)

  @manager_permissions [0, 1]

  @doc """
  Whether D4H makes this member one of the team's managers (#57): an OWNER or EDITOR who
  isn't retired and hasn't left. Operational status doesn't matter.
  """
  def manager?(%Member{} = member, now) do
    member.d4h_permission in @manager_permissions and member.d4h_status != "RETIRED" and
      current?(member, now)
  end

  def permission_label(0), do: "Owner"
  def permission_label(1), do: "Editor"
  def permission_label(2), do: "Member"
  def permission_label(3), do: "Member plus"
  def permission_label(4), do: "No access"
  def permission_label(_), do: "Unknown"

  @doc """
  The team's managers, by name, leaving out the team key's own account: a "SAR Duty"
  member would otherwise pass as one.
  """
  def get_managers(%Team{} = team, now) do
    Member
    |> where([m], m.team_id == ^team.id and m.d4h_permission in @manager_permissions)
    |> order_by([m], asc: m.name)
    |> Repo.all()
    |> Enum.filter(&(manager?(&1, now) and &1.d4h_member_id != team.d4h_access_key_member_id))
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

  def include_primary_and_secondary_minutes(query, team, year) do
    query
    |> join_activity_minutes(team, year, Activity.primary_hours_tag())
    |> join_activity_minutes(team, year, Activity.secondary_hours_tag())
    |> join_tax_credit_letter_id(year)
    |> select_primary_secondary_minutes_summary()
  end

  defp join_activity_minutes(query, team, year, tag) do
    from(
      m in query,
      left_join: a in subquery(Attendance.tagged_minutes_summary(team, year, [tag])),
      on: m.id == a.member_id
    )
  end

  defp join_tax_credit_letter_id(query, year) do
    from(
      m in query,
      left_join: tcl in assoc(m, :tax_credit_letters),
      on: tcl.year == ^year
    )
  end

  defp select_primary_secondary_minutes_summary(query) do
    from(
      [m, primary, secondary, tcl] in query,
      select: %{
        member: m,
        tax_credit_letter_id: tcl.id,
        tax_credit_letter_ref_id: tcl.ref_id,
        primary_minutes: fragment("? as primary_minutes", coalesce(primary.minutes, 0)),
        secondary_minutes: fragment("? as secondary_minutes", coalesce(secondary.minutes, 0)),
        total_minutes:
          fragment(
            "(? + ?) as total_minutes",
            coalesce(primary.minutes, 0),
            coalesce(secondary.minutes, 0)
          )
      }
    )
  end
end
