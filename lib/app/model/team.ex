defmodule App.Model.Team do
  use App, :model

  alias App.Field.EncryptedString
  alias App.Field.TrimmedString
  alias App.Model.Member
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Model.TeamLoginGrant
  alias App.Repo
  alias App.Validate

  # Paths name a team by its subdomain: ~p"/teams/#{team}/members".
  @derive {Phoenix.Param, key: :subdomain}
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
    field :d4h_access_key_owner, :string
    field :d4h_access_key_member_id, :integer
    # The settings form takes a replacement key here, so the saved key never
    # goes back to the page.
    field :new_d4h_access_key, TrimmedString, virtual: true, redact: true
    field :d4h_refresh_result, :string
    field :d4h_refreshed_at, :utc_datetime_usec
    # Set by an admin on the organization's page, never cast from a form.
    belongs_to :organization, Organization
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
      :d4h_access_key_owner,
      :d4h_access_key_member_id,
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
    |> preload(:organization)
    |> Repo.all()
  end

  @doc """
  The teams this email manages: it matches a member who is a D4H Owner or Editor, isn't
  retired, and hasn't left (App.Model.Member.manager?/2). The team key's own member never
  counts when it's a "SAR Duty" account; a person whose own key is the team key still
  manages the team. Teams an admin let the email into (App.Model.TeamLoginGrant) count
  too. By name.
  """
  def get_managed_by(email, now) when is_binary(email) do
    (teams_managed_in_d4h(email, now) ++ teams_granted(email))
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end

  defp teams_managed_in_d4h(email, now) do
    Team
    |> join(:inner, [t], m in subquery(managers_with_email(email, now)), on: m.team_id == t.id)
    |> where(
      [t, m],
      is_nil(t.d4h_access_key_member_id) or t.d4h_access_key_member_id != m.d4h_member_id or
        not like(fragment("lower(replace(?, ' ', ''))", t.d4h_access_key_owner), "%sarduty%")
    )
    |> distinct(true)
    |> Repo.all()
  end

  # Teams an admin let this email into with App.Model.TeamLoginGrant.
  defp teams_granted(email) do
    email = email |> String.trim() |> String.downcase()

    Team
    |> join(:inner, [t], g in TeamLoginGrant, on: g.team_id == t.id)
    |> where([t, g], g.email == ^email)
    |> Repo.all()
  end

  # The same bar as App.Model.Member.manager?/2, as a query.
  defp managers_with_email(email, now) do
    email = email |> String.trim() |> String.downcase()

    from m in Member,
      where:
        fragment("lower(?)", m.email) == ^email and m.d4h_permission in [0, 1] and
          (is_nil(m.d4h_status) or m.d4h_status != "RETIRED") and
          (is_nil(m.left_at) or m.left_at > ^now),
      select: %{team_id: m.team_id, d4h_member_id: m.d4h_member_id}
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

  @doc """
  How a `d4h_refresh_result` reads: `:never` refreshed, `:ok`, `:failed` (anything the
  worker writes as "Error: …"), or `:refreshing` (a stage's progress).
  """
  def refresh_state(nil), do: :never
  def refresh_state("OK"), do: :ok
  def refresh_state("Error:" <> _message), do: :failed
  def refresh_state(result) when is_binary(result), do: :refreshing

  @doc """
  Whether the team key comes from a D4H account set up for SAR Duty rather than a
  person's, judged by the member name. A person's key dies when they leave the team.
  """
  def key_owner_is_sar_duty?(%Team{d4h_access_key_owner: owner}) when is_binary(owner),
    do: String.match?(owner, ~r/sar\s*duty/i)

  def key_owner_is_sar_duty?(%Team{}), do: false

  def logo_path(team_subdomain) do
    logo_path = System.fetch_env!("TEAM_LOGO_PATH")
    Path.join(logo_path, "#{team_subdomain}.png")
  end

  @doc """
  The saved logo's path, or nil when there is none: the team has not refreshed yet, or
  has no profile image in D4H.
  """
  def logo_file(team_subdomain) do
    path = logo_path(team_subdomain)
    if File.regular?(path), do: path
  end
end
