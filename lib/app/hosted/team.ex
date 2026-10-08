defmodule App.Hosted.Team do
  use App, :model

  # A team whose records SAR Duty keeps itself, served by App.Hosted.API. Its id is the
  # team's d4h_team_id on App.Model.Team.
  schema "hosted_teams" do
    field :title, :string
    field :subdomain, :string
    field :timezone, :string
    field :lat, :float
    field :lng, :float
    field :access_key_hash, :binary, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:title, :subdomain, :timezone, :lat, :lng])
    |> validate_required([:title, :subdomain, :timezone])
    |> validate_length(:title, max: 100)
    |> unique_constraint(:subdomain)
  end
end
