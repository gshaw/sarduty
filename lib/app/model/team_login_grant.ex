defmodule App.Model.TeamLoginGrant do
  use App, :model

  alias App.Model.Event
  alias App.Model.Team
  alias App.Model.TeamLoginGrant
  alias App.Repo

  # An email let into a team on top of its D4H managers. Emails are stored lowercase.
  schema "team_login_grants" do
    belongs_to :team, Team
    field :email, :string
    field :reason, :string
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Lets an email into a team, found by subdomain. For admins, through
  `bin/sarduty rpc`: `App.Model.TeamLoginGrant.grant!("teamsub", "office@example.org", "why")`.
  """
  def grant!(subdomain, email, reason) do
    team = Repo.get_by!(Team, subdomain: subdomain)

    grant =
      %TeamLoginGrant{team_id: team.id}
      |> cast(%{email: email, reason: reason}, [:email, :reason])
      |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
      |> validate_required([:email])
      |> unique_constraint([:team_id, :email])
      |> Repo.insert!()

    Event.record!(:login_grant_added, team_id: team.id, data: %{who: Event.who(grant.email)})
    grant
  end

  def revoke!(subdomain, email) do
    team = Repo.get_by!(Team, subdomain: subdomain)
    email = email |> String.trim() |> String.downcase()

    result =
      TeamLoginGrant
      |> where([g], g.team_id == ^team.id and g.email == ^email)
      |> Repo.delete_all()

    if elem(result, 0) > 0,
      do: Event.record!(:login_grant_removed, team_id: team.id, data: %{who: Event.who(email)})

    result
  end

  def get_for_team(%Team{} = team) do
    TeamLoginGrant
    |> where([g], g.team_id == ^team.id)
    |> order_by([g], asc: g.email)
    |> Repo.all()
  end

  def get_all do
    TeamLoginGrant |> order_by([g], asc: g.email) |> Repo.all()
  end
end
