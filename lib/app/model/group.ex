defmodule App.Model.Group do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Team
  alias App.Repo

  schema "groups" do
    belongs_to :team, Team
    has_many :group_members, GroupMember
    field :d4h_group_id, :integer
    field :title, TrimmedString
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%Group{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :team_id,
      :d4h_group_id,
      :title
    ])
    |> validate_required([
      :team_id,
      :d4h_group_id,
      :title
    ])
  end

  def scope(q, team_id: team_id), do: where(q, team_id: ^team_id)

  def get_all(team_id) do
    Group
    |> where([r], r.team_id == ^team_id)
    |> order_by([r], asc: r.title)
    |> Repo.all()
  end

  def get_by(params), do: Repo.get_by(Group, params)

  def insert!(params) do
    changeset = Group.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%Group{} = record, params) do
    changeset = Group.build_changeset(record, params)
    Repo.update!(changeset)
  end
end
