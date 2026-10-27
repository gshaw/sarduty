defmodule Web.Search do
  @moduledoc """
  What global search (#473) finds for the person searching, and where each result opens.
  App.ViewData.Search matches and ranks; this decides the kinds they may see, from the
  `access` of the page each kind opens, and adds the side navigation's pages.

  Every team page for one record, `/teams/:subdomain/…/:id`, is a kind here or is in
  `not_searched/0` with a reason; test/web/search_test.exs checks it. See docs/search.md.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: Web.Endpoint,
    router: Web.Router,
    statics: Web.static_paths()

  alias App.Model.MemberAwayPeriod
  alias App.Model.Team
  alias App.ViewData.Search
  alias Web.UserAuth

  # The page each kind opens. Its `access` decides who finds the kind.
  @live_views %{
    member: Web.MemberLive,
    activity: Web.ActivityLive,
    equipment: Web.EquipmentItemLive,
    qualification: Web.QualificationLive,
    group: Web.GroupLive,
    endorsement: Web.EndorsementFormLive,
    template: Web.TemplateFormLive,
    chore: Web.ChoreLive,
    certificate: Web.CertificateLive
  }

  @doc "The page each kind of record opens."
  def live_views, do: @live_views

  @doc "Team pages for one record that search leaves out, and why."
  def not_searched,
    do: %{
      Web.TaxCreditLetterLive => "A letter holds personal text; find the member instead.",
      Web.Settings.ChoreCategoryFormLive => "A setting, found from Team settings."
    }

  @doc """
  The groups for `query` on `team`, best first, each hit with its `path`. `sections` is the
  side navigation the person sees, from Web.Navigation.sections/3, so pages they can't open
  never show. `team_admin?` and `member?` are as the page assigned them.
  """
  def run(team, query, opts) do
    team_admin? = Keyword.fetch!(opts, :team_admin?)

    search_opts = [
      kinds: kinds(team, team_admin?, Keyword.fetch!(opts, :member?)),
      pages: opts |> Keyword.get(:sections, []) |> pages(),
      now: Keyword.get(opts, :now, DateTime.utc_now())
    ]

    team
    |> Search.run(query, search_opts)
    |> Enum.map(fn group ->
      %{group | hits: Enum.map(group.hits, &shown(&1, group.kind, team, team_admin?))}
    end)
  end

  @recent 5

  @doc """
  The recent picks (#473) from `keys`, the browser's list of `"kind:id"` strings, newest
  first, as one group, or `[]`. Takes the same options as run/3, so a pick this person can't
  open, on another team, or gone, is left out.
  """
  def recent(team, keys, opts) when is_list(keys) do
    team_admin? = Keyword.fetch!(opts, :team_admin?)

    search_opts = [
      kinds: kinds(team, team_admin?, Keyword.fetch!(opts, :member?)),
      pages: opts |> Keyword.get(:sections, []) |> pages()
    ]

    keys =
      keys
      |> Enum.flat_map(&parse_key/1)
      |> Enum.uniq()
      |> Enum.take(@recent)

    case Search.find(team, keys, search_opts) do
      [] ->
        []

      hits ->
        [
          %{
            kind: :recent,
            more?: false,
            hits: Enum.map(hits, &shown(&1, &1.kind, team, team_admin?))
          }
        ]
    end
  end

  def recent(_team, _keys, _opts), do: []

  # "member:12" or "page:tax-credit-letters", from the browser, so nothing is trusted: the
  # kind must be one search knows, and a record's id a number.
  defp parse_key(key) when is_binary(key) do
    with [kind, id] <- String.split(key, ":", parts: 2),
         {:ok, kind} <- parse_kind(kind),
         {:ok, id} <- parse_id(kind, id) do
      [{kind, id}]
    else
      _other -> []
    end
  end

  defp parse_key(_key), do: []

  defp parse_kind(text) do
    case Enum.find(Search.kinds(), &(Atom.to_string(&1) == text)) do
      nil -> :error
      kind -> {:ok, kind}
    end
  end

  defp parse_id(:page, id), do: {:ok, id}

  defp parse_id(_kind, id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _other -> :error
    end
  end

  @doc """
  A hit's key for the recent picks: `"member:12"`.
  """
  def key(hit), do: "#{hit.kind}:#{hit.id}"

  @doc """
  The kinds whose page this person opens on `team`. Pages are always in: they are the ones
  they see. Chores and certificates only on a team with them on, as their pages.
  """
  def kinds(team, team_admin?, member?) do
    Enum.filter(Search.kinds(), fn
      :page -> true
      :chore -> Team.chores?(team) and opens?(:chore, team_admin?, member?)
      :certificate -> Team.certificates?(team) and opens?(:certificate, team_admin?, member?)
      kind -> opens?(kind, team_admin?, member?)
    end)
  end

  defp opens?(kind, team_admin?, member?),
    do: kind |> page_access() |> UserAuth.opens?(team_admin?, member?)

  defp pages(sections) do
    for link <- List.flatten(sections), do: %{id: link.key, title: link.label, path: link.path}
  end

  # A hit with where it opens, and a member's standing as the person searching sees it.
  defp shown(hit, kind, team, team_admin?) do
    hit = Map.put_new(hit, :path, hit_path(kind, team, hit.id))

    if kind == :member,
      do: Map.update!(hit, :standing, &MemberAwayPeriod.visible_standing(&1, team_admin?)),
      else: hit
  end

  defp page_access(kind), do: @live_views |> Map.fetch!(kind) |> UserAuth.page_access()

  @doc "Where a hit opens."
  def hit_path(:member, team, id), do: ~p"/teams/#{team}/members/#{id}"
  def hit_path(:activity, team, id), do: ~p"/teams/#{team}/activities/#{id}"
  def hit_path(:equipment, team, id), do: ~p"/teams/#{team}/equipment/#{id}"
  def hit_path(:qualification, team, id), do: ~p"/teams/#{team}/qualifications/#{id}"
  def hit_path(:group, team, id), do: ~p"/teams/#{team}/groups/#{id}"
  def hit_path(:endorsement, team, id), do: ~p"/teams/#{team}/endorsements/#{id}"
  def hit_path(:template, team, id), do: ~p"/teams/#{team}/templates/#{id}"
  def hit_path(:chore, team, id), do: ~p"/teams/#{team}/chores/#{id}"
  def hit_path(:certificate, team, id), do: ~p"/teams/#{team}/certificates/#{id}"
  def hit_path(:page, _team, _id), do: nil

  @doc "The list a group's \"All …\" link opens, filtered by `query`, or nil when it has none."
  def more_path(:member, team, query),
    do: ~p"/teams/#{team}/members?#{[q: query, standing: "all"]}"

  def more_path(:activity, team, query), do: ~p"/teams/#{team}/activities?#{[q: query]}"
  def more_path(:equipment, team, query), do: ~p"/teams/#{team}/equipment?#{[q: query]}"
  def more_path(:qualification, team, query), do: ~p"/teams/#{team}/qualifications?#{[q: query]}"
  def more_path(_kind, _team, _query), do: nil
end
