defmodule App.Model.GroupMember do
  use App, :model

  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Repo

  schema "group_members" do
    belongs_to :group, Group
    belongs_to :member, Member
    field :d4h_group_membership_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%GroupMember{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :group_id,
      :member_id,
      :d4h_group_membership_id
    ])
    |> validate_required([
      :group_id,
      :member_id,
      :d4h_group_membership_id
    ])
  end

  def get_by(params), do: Repo.get_by(GroupMember, params)

  def insert!(params) do
    changeset = GroupMember.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%GroupMember{} = record, params) do
    changeset = GroupMember.build_changeset(record, params)
    Repo.update!(changeset)
  end
end
