defmodule App.Model.Member do
  use App, :model

  alias App.Field.EncryptedString
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo
  alias App.Validate

  schema "members" do
    belongs_to :team, Team
    has_many :attendances, Attendance, where: [status: "attending"]
    has_many :activities, through: [:attendances, :activity]
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

  # def delete(%Member{} = record), do: Repo.delete(record)
end
