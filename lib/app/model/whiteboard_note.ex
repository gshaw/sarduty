defmodule App.Model.WhiteboardNote do
  use App, :model

  alias App.Model.Team
  alias App.Model.WhiteboardNote
  alias App.Repo

  # A copy of one note on the team's D4H whiteboard (#515), kept by the sync. Not history:
  # the sync replaces the team's notes with D4H's. A note is live until its archived_at,
  # and one with none stays live.
  schema "whiteboard_notes" do
    belongs_to :team, Team
    field :d4h_whiteboard_note_id, :integer
    field :text, :string
    field :url, :string
    field :important, :boolean, default: false
    field :owner_kind, Ecto.Enum, values: [:team, :organization], default: :team
    field :archived_at, :utc_datetime
    field :d4h_created_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end

  @fields [:d4h_whiteboard_note_id, :text, :url, :important, :owner_kind, :archived_at]

  @doc "A row's fields from a `D4H.WhiteboardNote`, for an insert or an upsert."
  def fields_from(%App.Adapter.D4H.WhiteboardNote{} = note) do
    note
    |> Map.take(@fields)
    |> Map.put(:d4h_created_at, note.created_at)
  end

  @doc "The team's live notes: Important first, then the newest."
  def live(%Team{} = team, now) do
    team
    |> live_query(now)
    |> order_by([n], desc: n.important, desc: n.d4h_created_at, desc: n.id)
    |> Repo.all()
  end

  @doc "One page of the team's archived notes, the newest first. An `App.Page`."
  def archived(%Team{} = team, now, page \\ 1) do
    team
    |> archived_query(now)
    |> order_by([n], desc: n.archived_at, desc: n.id)
    |> Repo.paginate(page: page)
  end

  @doc "How many notes are live and archived, for the Whiteboard page's stat switch."
  def counts(%Team{} = team, now) do
    %{
      live: team |> live_query(now) |> Repo.aggregate(:count),
      archived: team |> archived_query(now) |> Repo.aggregate(:count)
    }
  end

  @doc "One of the team's notes by its local id, or nil."
  def get_for_team(%Team{} = team, id) do
    WhiteboardNote
    |> where([n], n.team_id == ^team.id and n.id == ^id)
    |> Repo.one()
  end

  @doc "Whether the note is the team's own, so a team admin can change it."
  def team_note?(%WhiteboardNote{owner_kind: kind}), do: kind == :team

  @doc "The last day a note shows, in the team's zone: the day before its archive time."
  def last_day(%WhiteboardNote{archived_at: nil}, _timezone), do: nil

  def last_day(%WhiteboardNote{archived_at: at}, timezone),
    do: at |> DateTime.add(-1, :second) |> Service.Period.today(timezone)

  defp live_query(team, now) do
    where(
      WhiteboardNote,
      [n],
      n.team_id == ^team.id and (is_nil(n.archived_at) or n.archived_at > ^now)
    )
  end

  defp archived_query(team, now),
    do: where(WhiteboardNote, [n], n.team_id == ^team.id and n.archived_at <= ^now)
end
