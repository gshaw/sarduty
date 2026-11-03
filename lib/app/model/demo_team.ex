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
    field :code_hash, :binary, redact: true
    field :code_sent_at, :utc_datetime
    field :code_misses, :integer, default: 0
    timestamps(type: :utc_datetime)
  end

  @days 7
  @code_hours 24
  @code_max_misses 5

  @doc "How long a demo lives, from when it's built."
  def days, do: @days

  @doc "The demo for this email, or nil."
  def get_by_email(email) when is_binary(email),
    do: Repo.get_by(DemoTeam, email: email |> String.trim() |> String.downcase())

  @doc "How many demos are live now, built or waiting to be opened."
  def live_count(now), do: DemoTeam |> where([d], d.expires_at > ^now) |> Repo.aggregate(:count)

  @doc "The demos past their day, oldest first."
  def expired(now),
    do: DemoTeam |> where([d], d.expires_at <= ^now) |> order_by(:expires_at) |> Repo.all()

  @doc "Built demos that go within a day and haven't been told."
  def to_warn(now) do
    soon = DateTime.add(now, 1, :day)

    DemoTeam
    |> where([d], not is_nil(d.team_id) and is_nil(d.warned_at))
    |> where([d], d.expires_at > ^now and d.expires_at <= ^soon)
    |> Repo.all()
  end

  @doc """
  A new six-digit code for the demo's link: `{code, changes}`. Only its hash is kept,
  keyed with the app's secret, as a login code's is.
  """
  def new_code(%DemoTeam{} = demo, now) do
    <<n::32>> = :crypto.strong_rand_bytes(4)
    code = n |> rem(1_000_000) |> Integer.to_string() |> String.pad_leading(6, "0")
    {code, %{code_hash: hash(demo, code), code_sent_at: now, code_misses: 0}}
  end

  @doc """
  Whether `code` opens the demo: its live code, under #{@code_hours} hours old and under
  #{@code_max_misses} misses. It works again until then, so a mail app that opens links
  to check them can't use it up. A miss counts against it.
  """
  def code_ok?(%DemoTeam{code_hash: hash} = demo, code, now) when is_binary(hash) do
    live? =
      demo.code_misses < @code_max_misses and
        DateTime.diff(now, demo.code_sent_at, :hour) < @code_hours

    code = (code || "") |> to_string() |> String.replace(~r/\s/, "")

    if live? and demo |> hash(code) |> Plug.Crypto.secure_compare(hash) do
      true
    else
      DemoTeam |> where(id: ^demo.id) |> Repo.update_all(inc: [code_misses: 1])
      false
    end
  end

  def code_ok?(%DemoTeam{}, _code, _now), do: false

  # cspell:ignore hmac -- the :crypto.mac/4 algorithm name
  defp hash(demo, code) do
    secret = Application.fetch_env!(:sarduty, Web.Endpoint)[:secret_key_base]
    :crypto.mac(:hmac, :sha256, secret, "demo:#{demo.id}:#{code}")
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
