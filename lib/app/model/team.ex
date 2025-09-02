defmodule App.Model.Team do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Team
  alias App.Repo
  alias App.Validate

  schema "teams" do
    field :name, TrimmedString
    field :subdomain, :string
    field :d4h_team_id, :integer
    field :d4h_api_host, :string
    field :mailing_address, TrimmedString
    field :authorized_by_name, TrimmedString
    field :lat, :float
    field :lng, :float
    field :timezone, :string
    field :d4h_refreshed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%Team{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :name,
      :subdomain,
      :d4h_team_id,
      :d4h_api_host,
      :d4h_refreshed_at,
      :mailing_address,
      :authorized_by_name,
      :lat,
      :lng,
      :timezone
    ])
    |> validate_required([
      :name,
      :subdomain,
      :d4h_team_id,
      :d4h_api_host,
      :lat,
      :lng,
      :timezone
    ])
    |> Validate.name(:name)
    |> Validate.address(:mailing_address)
    |> validate_length(:authorized_by_name, max: 250)
  end

  def get_all do
    Team
    |> order_by([t], desc: t.id)
    |> Repo.all()
  end

  def get(id), do: Repo.get(Team, id)
  def get!(id), do: Repo.get!(Team, id)
  def get_by(params), do: Repo.get_by(Team, params)

  def insert!(params) do
    changeset = Team.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update(%Team{} = record, params) do
    changeset = Team.build_changeset(record, params)
    Repo.update(changeset)
  end

  # def delete(%Team{} = record), do: Repo.delete(record)

  def logo_path(team_subdomain) do
    logo_path = System.fetch_env!("TEAM_LOGO_PATH")
    Path.join(logo_path, "#{team_subdomain}.png")
  end
end
