defmodule App.Model.DemoTeam do
  use App, :model

  import Ecto.Query

  alias App.Model.DemoTeam
  alias App.Model.Team
  alias App.Repo

  # A visitor's Try a demo (#857): their own copy of Coast Range SAR for 7 days, from a
  # name and an email. The row comes first and the team once the emailed link is opened.
  # Everything a demo team sends goes to `email`, once (App.Mailer), its cards and
  # letters say Sample, and it never texts. See docs/demo.md.
  schema "demo_teams" do
    field :name, :string, redact: true
    field :email, :string, redact: true
    belongs_to :team, Team
    field :expires_at, :utc_datetime
    field :warned_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @doc "The demo a team is, or nil for a real team."
  def for_team(%Team{id: id}), do: for_team(id)
  def for_team(nil), do: nil
  def for_team(team_id) when is_integer(team_id), do: Repo.get_by(DemoTeam, team_id: team_id)

  @doc "Whether the team is a visitor's demo copy."
  def demo?(%Team{id: id}), do: demo?(id)
  def demo?(nil), do: false

  def demo?(team_id) when is_integer(team_id),
    do: DemoTeam |> where(team_id: ^team_id) |> Repo.exists?()

  @doc "The ids of every demo team, for queries that leave them out."
  def team_ids_query, do: from(d in DemoTeam, where: not is_nil(d.team_id), select: d.team_id)

  @doc """
  The toast after a demo team's send, saying where its one copy went, or nil on a real
  team.
  """
  def copy_text(team) do
    case for_team(team) do
      nil -> nil
      demo -> "Your demo sent one copy, to #{demo.email}."
    end
  end

  @doc """
  Splits what a send would email into what really goes and what doesn't: on a demo team,
  only the first of `items` goes (to the visitor, App.Mailer.for_team/3), so a send to
  15 members is one email. A real team's all go.
  """
  def one_copy(team, items) do
    if demo?(team), do: Enum.split(items, 1), else: {items, []}
  end
end
