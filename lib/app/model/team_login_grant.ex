defmodule App.Model.TeamLoginGrant do
  use App, :model

  alias App.Accounts.User
  alias App.Field.TrimmedString
  alias App.Model.Event
  alias App.Model.Team
  alias App.Model.TeamLoginGrant
  alias App.Repo
  alias App.Validate

  # An email let into a team on top of its D4H managers. A grant can do everything a team
  # admin does. SAR Duty admins add and remove them on the team's admin page,
  # /admin/teams/:id (#513). Emails are stored lowercase.
  schema "team_login_grants" do
    belongs_to :team, Team
    field :email, :string, redact: true
    field :reason, TrimmedString, redact: true
    belongs_to :added_by_user, User
    timestamps(type: :utc_datetime_usec)
  end

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [:email, :reason])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:email], message: "Enter an email.")
    |> Validate.email(:email)
    |> validate_length(:reason, max: 200)
    |> unique_constraint([:team_id, :email],
      error_key: :email,
      message: "This email has a login grant already."
    )
  end

  @doc """
  Lets an email into the team. `{:ok, grant}`, or `{:error, changeset}` for a bad or
  repeated email. `user` is who acted, or nil from a console.
  """
  def add(%Team{} = team, params, user) do
    changeset =
      build_changeset(
        %TeamLoginGrant{team_id: team.id, added_by_user_id: user && user.id},
        params
      )

    with {:ok, grant} <- Repo.insert(changeset) do
      Event.record!(:login_grant_added,
        team_id: team.id,
        user_id: user && user.id,
        data: %{who: Event.who(grant.email)}
      )

      {:ok, grant}
    end
  end

  @doc """
  The same from `bin/sarduty rpc`, raising on a bad email:
  `App.Model.TeamLoginGrant.grant!(App.Model.Team.get_by(subdomain: "x"), "office@example.org", "why")`.
  """
  def grant!(%Team{} = team, email, reason) do
    {:ok, grant} = add(team, %{email: email, reason: reason}, nil)
    grant
  end

  @doc "Removes one of the team's grants. `{:ok, grant}`, or `{:error, :not_found}`."
  def remove(%Team{} = team, id, user) do
    case Repo.get_by(TeamLoginGrant, id: id, team_id: team.id) do
      nil ->
        {:error, :not_found}

      grant ->
        Repo.delete!(grant)

        Event.record!(:login_grant_removed,
          team_id: team.id,
          user_id: user && user.id,
          data: %{who: Event.who(grant.email)}
        )

        {:ok, grant}
    end
  end

  @doc "The same by email, from a console."
  def revoke!(%Team{} = team, email) do
    email = email |> String.trim() |> String.downcase()

    case Repo.get_by(TeamLoginGrant, team_id: team.id, email: email) do
      nil -> {:error, :not_found}
      grant -> remove(team, grant.id, nil)
    end
  end

  def get_for_team(%Team{} = team) do
    TeamLoginGrant
    |> where([g], g.team_id == ^team.id)
    |> order_by([g], asc: g.email)
    |> preload(:added_by_user)
    |> Repo.all()
  end

  def get_all do
    TeamLoginGrant |> order_by([g], asc: g.email) |> Repo.all()
  end
end
