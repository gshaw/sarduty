defmodule App.Model.Member do
  use App, :model

  alias App.Field.EncryptedString
  alias App.Model.Activity
  alias App.Model.Attendance
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
    has_many :member_qualification_awards, MemberQualificationAward
    has_many :qualifications, through: [:member_qualification_awards, :qualification]
    has_many :tax_credit_letters, TaxCreditLetter
    field :d4h_member_id, :integer
    field :ref_id, :string
    field :name, :string
    field :email, EncryptedString
    field :phone, EncryptedString
    field :address, EncryptedString
    field :coordinate, EncryptedString
    field :position, :string
    field :joined_at, :utc_datetime
    field :left_at, :utc_datetime
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
      :coordinate,
      :position,
      :joined_at,
      :left_at
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

  def get(id), do: Repo.get(Member, id)
  def get!(id), do: Repo.get!(Member, id)
  def get_by(params), do: Repo.get_by(Member, params)

  def insert!(params) do
    changeset = Member.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%Member{} = record, params) do
    changeset = Member.build_changeset(record, params)
    Repo.update!(changeset)
  end

  def include_primary_and_secondary_hours(query, year) do
    query
    |> join_activity_hours(year, Activity.primary_hours_tag())
    |> join_activity_hours(year, Activity.secondary_hours_tag())
    |> join_tax_credit_letter_id(year)
    |> select_primary_secondary_hours_summary()
  end

  defp join_activity_hours(query, year, tag) do
    from(
      m in query,
      left_join: a in subquery(Attendance.tagged_hours_summary(year, [tag])),
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

  defp select_primary_secondary_hours_summary(query) do
    from(
      [m, primary, secondary, tcl] in query,
      select: %{
        member: m,
        tax_credit_letter_id: tcl.id,
        tax_credit_letter_ref_id: tcl.ref_id,
        primary_hours: fragment("? as primary_hours", coalesce(primary.hours, 0)),
        secondary_hours: fragment("? as secondary_hours", coalesce(secondary.hours, 0)),
        total_hours:
          fragment(
            "(? + ?) as total_hours",
            coalesce(primary.hours, 0),
            coalesce(secondary.hours, 0)
          )
      }
    )
  end
end
