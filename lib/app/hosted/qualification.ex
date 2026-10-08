defmodule App.Hosted.Qualification do
  use App, :model

  schema "hosted_qualifications" do
    field :hosted_team_id, :integer
    field :title, :string
    field :description, :string
    field :expires_months_default, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(qualification, attrs) do
    qualification
    |> cast(attrs, [:title, :description, :expires_months_default])
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
    |> validate_number(:expires_months_default, greater_than_or_equal_to: 0)
  end
end
