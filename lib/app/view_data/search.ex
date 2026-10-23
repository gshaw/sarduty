defmodule App.ViewData.Search do
  @moduledoc """
  Global search (#473): a team's records and pages whose name, D4H number, or barcode
  matches every word typed, in any order. It reads the live tables on each search, with
  no index, so nothing can go stale; the largest team's activities take a few ms.

  `run/3` queries; `terms/1`, `score/3`, and `rank/3` are pure. See docs/search.md.
  """
  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Endorsement
  alias App.Model.EquipmentItem
  alias App.Model.Group
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Model.Template
  alias App.Repo

  @kinds [:member, :activity, :equipment, :qualification, :group, :endorsement, :template, :page]

  # Enough candidates that an exact name isn't cut before ranking, few enough to stay fast.
  @candidates 100
  @per_kind 5
  @max_terms 6
  @max_term_length 60

  @doc "Every kind search finds, in the order groups tie."
  def kinds, do: @kinds

  @doc """
  The groups matching `query`, best first: `[%{kind:, hits:, more?:}]`, with up to 5 hits
  each and `more?` when more matched. Only `kinds` are searched; `:page` searches `pages`,
  a list of `%{key:, title:, path:}`. A hit is `%{kind:, id:, title:, score:}` plus what
  its kind shows. Blank or wordless queries find nothing.
  """
  def run(%Team{} = team, query, opts) do
    kinds = Keyword.fetch!(opts, :kinds)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    case terms(query) do
      [] ->
        []

      terms ->
        kinds
        |> Enum.map(fn kind ->
          hits = candidates(kind, team, terms, opts)
          {kind, describe(kind, hits, team, now)}
        end)
        |> rank(terms, now)
    end
  end

  @doc """
  Pure. The words of `query`, lowercased, without a leading `#` (D4H numbers are shown
  as #02193). At most #{@max_terms} words of #{@max_term_length} characters each.
  """
  def terms(query) when is_binary(query) do
    query
    |> String.downcase()
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.map(&(&1 |> String.trim_leading("#") |> String.slice(0, @max_term_length)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(@max_terms)
  end

  def terms(_query), do: []

  @doc """
  Pure. How well a record matches the search's `terms`, from its `title` and `keys`
  (D4H number, barcode, serial). The database has already checked that every word is in
  one of them.

  100 a key is the whole search (#02193 finds 2193 too); 90 the title is; 80 the title
  starts with it; 60 every word starts a word of the title; 40 every word is in the title;
  20 otherwise.
  """
  def score(title, keys, terms) do
    phrase = Enum.join(terms, " ")
    title = String.downcase(title || "")

    cond do
      Enum.any?(keys, &key_match?(&1, phrase)) -> 100
      title == phrase -> 90
      String.starts_with?(title, phrase) -> 80
      Enum.all?(terms, &word_start?(title, &1)) -> 60
      Enum.all?(terms, &String.contains?(title, &1)) -> 40
      true -> 20
    end
  end

  defp key_match?(nil, _phrase), do: false

  defp key_match?(key, phrase) do
    key = String.downcase(key)
    key == phrase or zeroless(key) == zeroless(phrase)
  end

  defp zeroless(text) do
    case String.trim_leading(text, "0") do
      "" -> text
      trimmed -> trimmed
    end
  end

  defp word_start?(title, term) do
    title
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.any?(&String.starts_with?(&1, term))
  end

  @doc """
  Pure. Scores each kind's hits, keeps the best #{@per_kind}, and orders the groups by
  their best hit, ties in `kinds/0` order. Within a kind, equal scores put current
  members before retired ones, the activities nearest `now` first, and equipment in
  service first.
  """
  def rank(kind_hits, terms, now) do
    kind_hits
    |> Enum.map(fn {kind, hits} -> rank_kind(kind, hits, terms, now) end)
    |> Enum.reject(&(&1.hits == []))
    |> Enum.sort_by(&{-hd(&1.hits).score, kind_order(&1.kind)})
  end

  defp rank_kind(kind, hits, terms, now) do
    sorted =
      hits
      |> Enum.map(&Map.put(&1, :score, score(&1.title, Map.get(&1, :keys, []), terms)))
      |> Enum.sort_by(&{-&1.score, tiebreak(kind, &1, now), String.downcase(&1.title)})

    %{kind: kind, hits: Enum.take(sorted, @per_kind), more?: length(sorted) > @per_kind}
  end

  defp kind_order(kind), do: Enum.find_index(@kinds, &(&1 == kind))

  defp tiebreak(:member, hit, _now), do: if(hit.standing == :retired, do: 1, else: 0)

  defp tiebreak(:activity, %{started_at: nil}, _now), do: :infinity

  defp tiebreak(:activity, hit, now), do: abs(DateTime.diff(hit.started_at, now))
  defp tiebreak(:equipment, hit, _now), do: if(hit.in_service?, do: 0, else: 1)
  defp tiebreak(_kind, _hit, _now), do: 0

  # Each kind's rows where every word is in one of its fields.

  defp candidates(:member, team, terms, _opts) do
    Member
    |> where([m], m.team_id == ^team.id)
    |> matching(terms, [:name, :ref_id])
    |> select([m], map(m, [:id, :name, :ref_id, :position, :left_at, :d4h_status, :not_a_person]))
    |> fetch()
    |> Enum.map(&Map.merge(&1, %{title: &1.name, keys: [&1.ref_id]}))
  end

  defp candidates(:activity, team, terms, _opts) do
    Activity
    |> where([a], a.team_id == ^team.id)
    |> Activity.not_deleted()
    |> matching(terms, [:title, :ref_id, :tracking_number])
    |> order_by([a], desc: a.started_at)
    |> select([a], map(a, [:id, :title, :ref_id, :tracking_number, :activity_kind, :started_at]))
    |> fetch()
    |> Enum.map(&Map.put(&1, :keys, [&1.ref_id, &1.tracking_number]))
  end

  defp candidates(:equipment, team, terms, _opts) do
    EquipmentItem
    |> where([i], i.team_id == ^team.id)
    |> matching(terms, [:title, :barcode, :serial])
    |> select([i], map(i, [:id, :title, :barcode, :serial, :status, :location_title]))
    |> fetch()
    |> Enum.map(&Map.put(&1, :keys, [&1.barcode, &1.serial]))
  end

  defp candidates(:qualification, team, terms, _opts), do: titled(Qualification, team, terms)
  defp candidates(:group, team, terms, _opts), do: titled(Group, team, terms)
  defp candidates(:template, team, terms, _opts), do: titled(Template, team, terms)

  defp candidates(:endorsement, team, terms, _opts) do
    Endorsement
    |> where([e], e.team_id == ^team.id)
    |> matching(terms, [:name])
    |> select([e], %{id: e.id, title: e.name})
    |> fetch()
  end

  # Pages match at the start of a word, so "ali" doesn't find Qualifications.
  defp candidates(:page, _team, terms, opts) do
    opts
    |> Keyword.get(:pages, [])
    |> Enum.filter(fn page ->
      title = String.downcase(page.title)
      Enum.all?(terms, &word_start?(title, &1))
    end)
  end

  defp titled(schema, team, terms) do
    schema
    |> where([r], r.team_id == ^team.id)
    |> matching(terms, [:title])
    |> select([r], %{id: r.id, title: r.title})
    |> fetch()
  end

  defp fetch(query), do: query |> limit(@candidates) |> Repo.all()

  # Every word in at least one field. LIKE ignores case for ASCII; % and _ typed in are
  # matched as themselves.
  defp matching(query, terms, fields) do
    Enum.reduce(terms, query, fn term, query ->
      pattern = "%" <> escape_like(term) <> "%"

      any_field =
        Enum.reduce(fields, dynamic([r], false), fn field, acc ->
          dynamic([r], ^acc or fragment("? LIKE ? ESCAPE '\\'", field(r, ^field), ^pattern))
        end)

      where(query, ^any_field)
    end)
  end

  defp escape_like(term), do: String.replace(term, ["\\", "%", "_"], &("\\" <> &1))

  # What each kind's hits show beside the title.

  defp describe(:member, hits, team, now) do
    today = Service.Period.today(now, team.timezone)
    ids = Enum.map(hits, & &1.id)

    away =
      team
      |> MemberAwayPeriod.away_query(today)
      |> where([p], p.member_id in ^ids)
      |> Repo.all()
      |> Map.new(&{&1.member_id, &1.away_until})

    Enum.map(hits, fn hit ->
      Map.put(hit, :standing, standing(hit, Map.get(away, hit.id), now))
    end)
  end

  defp describe(:equipment, hits, _team, _now),
    do: Enum.map(hits, &Map.put(&1, :in_service?, &1.status not in ["retired", "lost"]))

  defp describe(_kind, hits, _team, _now), do: hits

  # MemberAwayPeriod.standing/4 with the away period's last day only.
  defp standing(hit, away_until, now) do
    cond do
      not Member.current?(hit, now) -> :retired
      hit.not_a_person -> :not_a_person
      away_until -> {:away, away_until}
      true -> :active
    end
  end
end
