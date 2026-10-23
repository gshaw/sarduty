defmodule Web.SearchTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias Web.Navigation

  @now ~U[2026-10-23 19:00:00Z]

  # A new page for one record fails here until search finds its kind, or not_searched/0
  # says why it doesn't (#473).
  test "every team page for one record is searched or says why not" do
    record_pages =
      for %{path: path, metadata: %{phoenix_live_view: {view, _action, _opts, _extra}}} <-
            Web.Router.__routes__(),
          String.starts_with?(path, "/teams/:subdomain/"),
          String.ends_with?(path, "/:id"),
          uniq: true,
          do: view

    searched = Web.Search.live_views() |> Map.values() |> MapSet.new()
    skipped = Web.Search.not_searched() |> Map.keys() |> MapSet.new()

    for view <- record_pages do
      assert view in searched or view in skipped,
             "#{inspect(view)} opens one record: add its kind to Web.Search, or to not_searched/0 with a reason"
    end

    assert MapSet.disjoint?(searched, skipped)
    assert MapSet.subset?(skipped, MapSet.new(record_pages))
  end

  describe "run/3" do
    setup do
      team = team_fixture()
      member_fixture(team, %{name: "Rope Rider"})
      activity = activity_fixture(team, %{title: "Rope night"})
      %{team: team, activity: activity}
    end

    test "a team admin finds every kind, each with where it opens", %{
      team: team,
      activity: activity
    } do
      groups = search(team, "rope", team_admin?: true, member?: false)

      assert groups |> Enum.map(& &1.kind) |> Enum.sort() == [:activity, :member]
      %{hits: [hit]} = Enum.find(groups, &(&1.kind == :activity))
      assert hit.path == "/teams/#{team.subdomain}/activities/#{activity.id}"
    end

    test "a member finds activities and their pages, not other members", %{team: team} do
      groups = search(team, "rope", team_admin?: false, member?: true)
      assert Enum.map(groups, & &1.kind) == [:activity]

      assert [%{kind: :page, hits: [%{title: "Your membership"}]}] =
               search(team, "membership", team_admin?: false, member?: true)
    end

    test "pages a member doesn't see aren't found", %{team: team} do
      assert search(team, "tax credit", team_admin?: false, member?: true) == []

      assert [%{kind: :page, hits: [%{path: path}]}] =
               search(team, "tax credit", team_admin?: true, member?: false)

      assert path == "/teams/#{team.subdomain}/tax-credit-letters"
    end
  end

  test "an All link opens the list with the search in place" do
    team = team_fixture()

    assert Web.Search.more_path(:member, team, "ali w") ==
             "/teams/#{team.subdomain}/members?q=ali+w&standing=all"

    assert Web.Search.more_path(:group, team, "x") == nil
  end

  defp search(team, query, who) do
    area = Navigation.area("/teams/#{team.subdomain}", team)
    sections = Navigation.sections(area, "/teams/#{team.subdomain}", who)
    Web.Search.run(team, query, Keyword.merge(who, sections: sections, now: @now))
  end
end
