defmodule App.Model.GroupMembershipChange do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Group
  alias App.Model.GroupMembershipChange
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  # One add or remove SAR Duty sent to D4H, with who asked for it. A failed
  # change is logged too, with D4H's error.
  schema "group_membership_changes" do
    belongs_to :team, Team
    belongs_to :member, Member
    belongs_to :user, User
    field :d4h_group_id, :integer
    field :action, Ecto.Enum, values: [:add, :remove]
    field :reason, :string
    field :error, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def insert!(%GroupMembershipChange{} = change), do: Repo.insert!(change)

  def recent_for_group(%Group{} = group, limit \\ 10) do
    GroupMembershipChange
    |> where([c], c.team_id == ^group.team_id and c.d4h_group_id == ^group.d4h_group_id)
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> limit(^limit)
    |> preload([:member, :user])
    |> Repo.all()
  end
end
