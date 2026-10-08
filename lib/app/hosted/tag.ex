defmodule App.Hosted.Tag do
  use App, :model

  schema "hosted_tags" do
    field :hosted_team_id, :integer
    field :title, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, max: 100)
  end
end
