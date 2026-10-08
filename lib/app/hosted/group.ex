defmodule App.Hosted.Group do
  use App, :model

  schema "hosted_groups" do
    field :hosted_team_id, :integer
    field :title, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, max: 50)
  end
end
