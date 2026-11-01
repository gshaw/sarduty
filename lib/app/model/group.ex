defmodule App.Model.Group do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRule
  alias App.Model.Team
  alias App.Repo

  schema "groups" do
    belongs_to :team, Team
    has_many :group_members, GroupMember
    field :d4h_group_id, :integer
    field :title, TrimmedString
    field :organization_owned, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%Group{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :team_id,
      :d4h_group_id,
      :title,
      :organization_owned
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

  @doc "The team's groups as `{title, id}`, by title, for a Group menu (#350)."
  def kinds(%Team{} = team), do: team.id |> get_all() |> Enum.map(&{&1.title, &1.id})

  @doc "The team's groups without rules, the lists kept by hand, by title."
  def get_kept_by_hand(team_id) do
    ruled = GroupRule.ruled_d4h_group_ids_query(team_id)

    Group
    |> where([g], g.team_id == ^team_id and g.d4h_group_id not in subquery(ruled))
    |> order_by([g], asc: g.title)
    |> Repo.all()
  end

  @doc ~s(The title as a picker lists it, with the organization for its groups: "Callout · BCSARA".)
  def label(%Group{organization_owned: true} = group, organization_name),
    do: "#{group.title} · #{organization_name}"

  def label(%Group{} = group, _organization_name), do: group.title

  def find!(team, id), do: Repo.get_by!(Group, id: id, team_id: team.id)
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
