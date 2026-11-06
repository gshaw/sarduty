defmodule App.Model.DemoTeam do
  use App, :model

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.DemoTeam
  alias App.Model.Team
  alias App.Repo

  # Try a demo (#857): a copy of Coast Range SAR of its own, opened by a link. The row
  # and its user come first, and the team the first time the link is opened. A demo
  # sends nothing: its email and texts go to its Outbox (App.Mailer, Twilio). Its
  # cards and letters say Sample. See docs/demo.md.
  #
  # A visitor's demo lasts 3 days from the build. A test's, made with the test key
  # for a script that checks SAR Duty on a live server, lasts the hours it asked for, and
  # stays out of the cap on visitors' demos.
  schema "demo_teams" do
    field :kind, Ecto.Enum, values: [:visitor, :test], default: :visitor
    field :name, :string, redact: true
    belongs_to :user, User
    belongs_to :team, Team
    field :expires_at, :utc_datetime
    field :seen_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @days 3
  @link_salt "demo link"
  @default_name "Taylor Brooks"

  @doc "How long a visitor's demo lives, from when it's built."
  def days, do: @days

  @doc "The visitor's member's name: theirs, or a made-up one."
  def visitor_name(%DemoTeam{name: name}) when name not in [nil, ""], do: name
  def visitor_name(%DemoTeam{}), do: @default_name

  @doc """
  The user the link logs in as, and the email of the visitor's member on the demo team.
  example.com never takes mail, so nothing sent to it can reach anyone.
  """
  def visitor_email(%DemoTeam{id: id}), do: "visitor-#{id}@example.com"

  @doc """
  The link that opens the demo: anyone with it is the visitor. It is signed rather than
  stored, so the banner can show it again, and it stops working when the demo goes.
  """
  def link_token(%DemoTeam{id: id}), do: Phoenix.Token.sign(Web.Endpoint, @link_salt, id)

  @doc "The demo a link opens, while it lives, or nil."
  def from_link_token(token, now) when is_binary(token) do
    # Unopened, a demo waits up to @days; opened, it lives @days from then. expires_at
    # decides; max_age only outlasts the longest a demo can live.
    max_age = (2 * @days + 1) * 86_400

    with {:ok, id} <- Phoenix.Token.verify(Web.Endpoint, @link_salt, token, max_age: max_age),
         %DemoTeam{} = demo <- Repo.get(DemoTeam, id),
         :gt <- DateTime.compare(demo.expires_at, now) do
      demo
    else
      _gone -> nil
    end
  end

  def from_link_token(_token, _now), do: nil

  @doc "How many visitors' demos are live now, built or waiting to be opened."
  def live_count(now) do
    DemoTeam
    |> where([d], d.kind == :visitor and d.expires_at > ^now)
    |> Repo.aggregate(:count)
  end

  @doc "The demos past their time, oldest first."
  def expired(now),
    do: DemoTeam |> where([d], d.expires_at <= ^now) |> order_by(:expires_at) |> Repo.all()

  @doc "The demo a user's link opened, or nil."
  def for_user(%User{id: id}), do: Repo.get_by(DemoTeam, user_id: id)

  @doc "The demo a team is, or nil for a real team."
  def for_team(%Team{id: id}), do: for_team(id)
  def for_team(nil), do: nil
  def for_team(team_id) when is_integer(team_id), do: Repo.get_by(DemoTeam, team_id: team_id)

  @doc "Whether the team is a demo copy."
  def demo?(%Team{id: id}), do: demo?(id)
  def demo?(nil), do: false

  def demo?(team_id) when is_integer(team_id),
    do: DemoTeam |> where(team_id: ^team_id) |> Repo.exists?()

  @doc "The ids of every demo team, for queries that leave them out."
  def team_ids_query, do: from(d in DemoTeam, where: not is_nil(d.team_id), select: d.team_id)

  @doc """
  The ids of demo teams `email` isn't the visitor of. A member there with that email
  logs in to nothing (#857): a visitor can add anyone's email to a member, and the demo
  would land in that person's account.
  """
  def team_ids_closed_to_query(email) do
    from(d in DemoTeam,
      left_join: u in assoc(d, :user),
      where: not is_nil(d.team_id),
      where: is_nil(u.id) or fragment("lower(?)", u.email) != ^String.downcase(email),
      select: d.team_id
    )
  end

  @doc """
  The ids of demo teams someone opened in the last hour: only these sync on the schedule,
  so 200 demos left open in tabs cost nothing.
  """
  def team_ids_in_use(now) do
    since = DateTime.add(now, -1, :hour)

    DemoTeam
    |> where([d], not is_nil(d.team_id) and d.seen_at > ^since)
    |> select([d], d.team_id)
    |> Repo.all()
  end

  @doc "Notes that someone has the demo open, at most every 5 minutes."
  def seen!(%DemoTeam{seen_at: seen_at} = demo, now) do
    if is_nil(seen_at) or DateTime.diff(now, seen_at, :minute) >= 5 do
      DemoTeam
      |> where(id: ^demo.id)
      |> Repo.update_all(set: [seen_at: DateTime.truncate(now, :second)])
    end

    :ok
  end
end
