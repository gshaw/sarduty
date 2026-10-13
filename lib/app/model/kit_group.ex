defmodule App.Model.KitGroup do
  use App, :model

  alias App.Model.Group
  alias App.Model.Kit

  # One group a kit invites to an activity (#162).
  schema "kit_groups" do
    belongs_to :kit, Kit
    belongs_to :group, Group
    timestamps(type: :utc_datetime_usec)
  end
end
