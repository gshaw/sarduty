defmodule App.Operation.BuildCardQualifications do
  import Ecto.Query

  alias App.Model.GroupRuleClause
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Team
  alias App.Repo

  @doc """
  The qualifications the team shows on ID cards that one member holds now: each named
  clause the team picked that the member meets.
  """
  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    clauses = team.id |> GroupRuleClause.get_all_named() |> Enum.filter(& &1.on_card)

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

    summarize(clauses, awards, now)
  end

  @doc """
  Pure. Clauses that share a name count as one, meeting it with a qualification from any
  of them. Returns `%{name, ends_at}` in name order for each one the member meets, where
  `ends_at` is when the latest current award ends, or nil when it doesn't. A clause the
  member doesn't meet is left off, so a card lists only what its holder has.
  """
  def summarize(clauses, awards, now) do
    active = Enum.filter(awards, &MemberQualificationAward.active?(&1, now))

    clauses
    |> Enum.group_by(& &1.name)
    |> Enum.flat_map(fn {name, same_name} ->
      ids = qualification_ids(same_name)
      active |> Enum.filter(&MapSet.member?(ids, &1.d4h_qualification_id)) |> summary(name)
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp qualification_ids(clauses) do
    for clause <- clauses,
        q <- clause.group_rule_clause_qualifications,
        into: MapSet.new(),
        do: q.d4h_qualification_id
  end

  defp summary([], _name), do: []

  defp summary(active, name) do
    ends_at =
      if Enum.any?(active, &is_nil(&1.ends_at)),
        do: nil,
        else: active |> Enum.map(& &1.ends_at) |> Enum.max(DateTime)

    [%{name: name, ends_at: ends_at}]
  end

  @doc "The status alone, for a pass field labelled with the name: \"Expires Nov 2026\"."
  def status_text(%{ends_at: nil}, _timezone), do: "No expiry"

  def status_text(%{ends_at: ends_at}, timezone),
    do: "Expires #{Service.Format.month_year(ends_at, timezone)}"

  @doc "One line per qualification for a page: \"First Aid — expires Nov 2026\"."
  def describe(%{ends_at: nil, name: name}, _timezone), do: "#{name} — no expiry"

  def describe(%{ends_at: ends_at, name: name}, timezone),
    do: "#{name} — expires #{Service.Format.month_year(ends_at, timezone)}"
end
