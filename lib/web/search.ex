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
    template: Web.TemplateFormLive
  }

  @doc "The page each kind of record opens."
  def live_views, do: @live_views

  @doc "Team pages for one record that search leaves out, and why."
  def not_searched,
    do: %{
      Web.ChoreLive => "A chore's words are the member's own; find the member instead.",
      Web.TaxCreditLetterLive => "A letter holds personal text; find the member instead.",
      Web.ProposedChangeLive =>
        "A proposal has no name of its own; its list is in the side navigation.",
      Web.Settings.ChoreCategoryFormLive => "A setting, found from Team settings."
    }

  @doc """
  The groups for `query` on `team`, best first, each hit with its `path`. `sections` is the
  side navigation the person sees, from Web.Navigation.sections/3, so pages they can't open
  never show. `team_admin?` and `member?` are as the page assigned them.
  """
  def run(team, query, opts) do
    search_opts = [
      kinds: kinds(Keyword.fetch!(opts, :team_admin?), Keyword.fetch!(opts, :member?)),
      pages: opts |> Keyword.get(:sections, []) |> pages(),
      now: Keyword.get(opts, :now, DateTime.utc_now())
    ]

    team
    |> Search.run(query, search_opts)
    |> Enum.map(fn group ->
      %{group | hits: Enum.map(group.hits, &with_path(&1, group.kind, team))}
    end)
  end

  # The kinds whose page this person opens. Pages are already the ones they see.
  defp kinds(team_admin?, member?) do
    Enum.filter(Search.kinds(), fn kind ->
      kind == :page or kind |> page_access() |> UserAuth.opens?(team_admin?, member?)
    end)
  end

  defp pages(sections) do
    for link <- List.flatten(sections), do: %{id: link.key, title: link.label, path: link.path}
  end

  defp with_path(hit, kind, team), do: Map.put_new(hit, :path, hit_path(kind, team, hit.id))

  defp page_access(kind), do: @live_views |> Map.fetch!(kind) |> UserAuth.page_access()

  @doc "Where a hit opens."
  def hit_path(:member, team, id), do: ~p"/teams/#{team}/members/#{id}"
  def hit_path(:activity, team, id), do: ~p"/teams/#{team}/activities/#{id}"
  def hit_path(:equipment, team, id), do: ~p"/teams/#{team}/equipment/#{id}"
  def hit_path(:qualification, team, id), do: ~p"/teams/#{team}/qualifications/#{id}"
  def hit_path(:group, team, id), do: ~p"/teams/#{team}/groups/#{id}"
  def hit_path(:endorsement, team, id), do: ~p"/teams/#{team}/endorsements/#{id}"
  def hit_path(:template, team, id), do: ~p"/teams/#{team}/templates/#{id}"
  def hit_path(:page, _team, _id), do: nil

  @doc "The list a group's \"All …\" link opens, filtered by `query`, or nil when it has none."
  def more_path(:member, team, query),
    do: ~p"/teams/#{team}/members?#{[q: query, standing: "all"]}"

  def more_path(:activity, team, query), do: ~p"/teams/#{team}/activities?#{[q: query]}"
  def more_path(:equipment, team, query), do: ~p"/teams/#{team}/equipment?#{[q: query]}"
  def more_path(:qualification, team, query), do: ~p"/teams/#{team}/qualifications?#{[q: query]}"
  def more_path(_kind, _team, _query), do: nil
end
