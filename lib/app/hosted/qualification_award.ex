defmodule App.Hosted.QualificationAward do
  use App, :model

  alias App.Hosted.Activity

  schema "hosted_qualification_awards" do
    field :hosted_team_id, :integer
    field :member_id, :integer
    field :qualification_id, :integer
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(award, attrs) do
    award
    |> cast(attrs, [:starts_at, :ends_at])
    |> validate_required([:starts_at])
    |> Activity.validate_ends_after_starts()
  end
end
