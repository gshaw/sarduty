defmodule App.Hosted.GroupMembership do
  use App, :model

  schema "hosted_group_memberships" do
    field :hosted_team_id, :integer
    field :group_id, :integer
    field :member_id, :integer
    timestamps(type: :utc_datetime_usec)
  end
end
