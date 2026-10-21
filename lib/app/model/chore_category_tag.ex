defmodule App.Model.ChoreCategoryTag do
  use App, :model

  alias App.Model.ChoreCategory
  alias App.Model.Tag

  # One other tag a chore category's D4H events get (#341), besides its hours tag.
  schema "chore_category_tags" do
    belongs_to :chore_category, ChoreCategory
    belongs_to :tag, Tag
    timestamps(type: :utc_datetime_usec)
  end
end
