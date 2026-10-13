defmodule App.Operation.BuildCardQualifications do
  import Ecto.Query

  alias App.Model.Endorsement
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Team
  alias App.Repo

  @doc """
  The endorsements the team lists on ID cards that one member holds now.
  """
  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    endorsements = team.id |> Endorsement.get_all() |> Enum.filter(& &1.on_card)

    awards =
      MemberQualificationAward
      |> join(:inner, [a], q in assoc(a, :qualification))
      |> where([a, q], a.member_id == ^member.id and q.team_id == ^team.id)
      |> select([a, q], %{
        d4h_qualification_id: q.d4h_qualification_id,
        starts_at: a.starts_at,
        ends_at: a.ends_at
      })
      |> Repo.all()

    summarize(endorsements, awards, now)
  end

  @doc """
  Pure. Returns `%{name, ends_at}` in name order for each endorsement the member holds,
  where `ends_at` is when the latest current award ends, or nil when it doesn't. One the
  member doesn't hold is left off, so a card lists only what its holder has.

  Only the highest tier shows: when a held endorsement's qualifications are a strict
  subset of another's, the stricter one stands for both. First Aid (70 hours or higher)
  hides First Aid (7 hours or higher).
  """
  def summarize(endorsements, awards, now) do
    active = Enum.filter(awards, &MemberQualificationAward.active?(&1, now))

    held =
      for endorsement <- endorsements,
          ids = endorsement |> Endorsement.qualification_ids() |> MapSet.new(),
          held = Enum.filter(active, &MapSet.member?(ids, &1.d4h_qualification_id)),
          held != [],
          do: {endorsement.name, ids, held}

    held
    |> Enum.reject(fn {_name, ids, _held} -> covered?(ids, held) end)
    |> Enum.flat_map(fn {name, _ids, held} -> summary(held, name) end)
    |> Enum.sort_by(& &1.name)
  end

  @doc "True when another of `endorsements`' qualification sets is a strict subset of `ids`."
  def covered?(ids, endorsements) do
    Enum.any?(endorsements, fn other ->
      other_ids = elem(other, 1)
      other_ids != ids and MapSet.subset?(other_ids, ids)
    end)
  end

  defp summary([], _name), do: []

  defp summary(active, name) do
    ends_at =
      if Enum.any?(active, &is_nil(&1.ends_at)),
        do: nil,
        else: active |> Enum.map(& &1.ends_at) |> Enum.max(DateTime)

    [%{name: name, ends_at: ends_at}]
  end

  @doc """
  The value beside the name in a pass field: when it ends, "Nov 2026", or blank when it
  doesn't. The name alone says the member holds it.
  """
  def status_text(%{ends_at: nil}, _timezone), do: ""
  def status_text(%{ends_at: ends_at}, timezone), do: Service.Format.month_year(ends_at, timezone)

  @doc "One line per qualification for a page: \"First Aid — expires Nov 2026\"."
  def describe(%{ends_at: nil, name: name}, _timezone), do: "#{name} — no expiry"

  def describe(%{ends_at: ends_at, name: name}, timezone),
    do: "#{name} — expires #{Service.Format.month_year(ends_at, timezone)}"
end
