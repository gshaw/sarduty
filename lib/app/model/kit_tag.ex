defmodule App.Model.KitTag do
  use App, :model

  alias App.Model.Kit
  alias App.Model.Tag

  # One tag a kit adds to an activity (#162).
  schema "kit_tags" do
    belongs_to :kit, Kit
    belongs_to :tag, Tag
    timestamps(type: :utc_datetime_usec)
  end
end
