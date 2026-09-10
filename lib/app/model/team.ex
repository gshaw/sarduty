defmodule App.Model.Team do
  use App, :model

  alias App.Accounts.User
  alias App.Field.EncryptedString
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
    field :d4h_access_key, EncryptedString, redact: true
    field :d4h_access_key_saved_at, :utc_datetime_usec
    # The settings form takes a replacement key here, so the saved key never
    # goes back to the page.
    field :new_d4h_access_key, TrimmedString, virtual: true, redact: true
    field :d4h_refresh_result, :string
    field :d4h_refreshed_at, :utc_datetime_usec
    has_many :users, User
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%Team{}, params)

  # Only what a team manager may edit. d4h_team_id and the saved key are not
  # castable here; UpdateTeamSettings sets the key after checking it with D4H.
  def build_settings_changeset(data, params \\ %{}) do
    data
    |> cast(params, [:name, :mailing_address, :authorized_by_name, :new_d4h_access_key])
    |> validate_required([:name])
    |> Validate.name(:name)
    |> Validate.address(:mailing_address)
    |> validate_length(:authorized_by_name, max: 250)
    |> validate_length(:new_d4h_access_key, min: 5, max: 2000)
  end

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :name,
      :subdomain,
      :d4h_team_id,
      :d4h_api_host,
      :d4h_access_key,
      :d4h_access_key_saved_at,
      :d4h_refresh_result,
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

  def get_all_with_users do
    users = from u in User, order_by: u.email

    Team
    |> order_by([t], desc: t.id)
    |> preload(users: ^users)
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
