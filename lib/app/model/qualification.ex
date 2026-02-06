defmodule App.Model.Qualification do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Repo

  schema "qualifications" do
    belongs_to :team, Team
    has_many :member_qualification_awards, MemberQualificationAward
    field :d4h_qualification_id, :integer
    field :title, TrimmedString
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%Qualification{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :team_id,
      :d4h_qualification_id,
      :title
    ])
    |> validate_required([
      :team_id,
      :d4h_qualification_id,
      :title
    ])
  end

  def scope(q, team_id: team_id), do: where(q, team_id: ^team_id)

  def get_all(team_id) do
    Qualification
    |> where([r], r.team_id == ^team_id)
    |> order_by([r], asc: r.title)
    |> Repo.all()
  end

  def get_by(params), do: Repo.get_by(Qualification, params)

  def insert!(params) do
    changeset = Qualification.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%Qualification{} = record, params) do
    changeset = Qualification.build_changeset(record, params)
    Repo.update!(changeset)
  end
end
