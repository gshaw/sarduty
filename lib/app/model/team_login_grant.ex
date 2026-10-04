defmodule App.Model.TeamLoginGrant do
  use App, :model

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

    %TeamLoginGrant{team_id: team.id}
    |> cast(%{email: email, reason: reason}, [:email, :reason])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:email])
    |> unique_constraint([:team_id, :email])
    |> Repo.insert!()
  end

  def revoke!(subdomain, email) do
    team = Repo.get_by!(Team, subdomain: subdomain)
    email = email |> String.trim() |> String.downcase()

    TeamLoginGrant
    |> where([g], g.team_id == ^team.id and g.email == ^email)
    |> Repo.delete_all()
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
