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

    test "a member finds activities, members, and their pages (#440)", %{team: team} do
      groups = search(team, "rope", team_admin?: false, member?: true)
      assert groups |> Enum.map(& &1.kind) |> Enum.sort() == [:activity, :member]

      assert [%{kind: :page, hits: [%{title: "Your membership"}]}] =
               search(team, "membership", team_admin?: false, member?: true)
    end

    # Away is often leave: only team admins see it (#440). Retired comes from D4H, and Not
    # a person keeps a team account from passing for a teammate.
    test "a member sees another member's standing unless away", %{team: team} do
      away = member_fixture(team, %{name: "Sky Away"})
      away_period_fixture(away, ~D[2026-10-01], ~D[2026-12-31])
      member_fixture(team, %{name: "Sky Bot", not_a_person: true})
      member_fixture(team, %{name: "Sky Gone", d4h_status: "RETIRED"})

      standings = fn who ->
        [%{hits: hits}] = search(team, "sky", who)
        Map.new(hits, &{&1.title, &1.standing})
      end

      assert %{
               "Sky Away" => {:away, ~D[2026-12-31]},
               "Sky Bot" => :not_a_person,
               "Sky Gone" => :retired
             } = standings.(team_admin?: true, member?: false)

      assert standings.(team_admin?: false, member?: true) ==
               %{"Sky Away" => :active, "Sky Bot" => :not_a_person, "Sky Gone" => :retired}
    end

    test "pages a member doesn't see aren't found", %{team: team} do
      assert search(team, "tax credit", team_admin?: false, member?: true) == []

      assert [%{kind: :page, hits: [%{path: path}]}] =
               search(team, "tax credit", team_admin?: true, member?: false)

      assert path == "/teams/#{team.subdomain}/tax-credit-letters"
    end
  end

  describe "Get help (#780)" do
    test "each of its words finds it, for a member and for a team admin" do
      team = team_fixture()

      for who <- [[team_admin?: false, member?: true], [team_admin?: true, member?: false]],
          word <- ~w(help support contact question problem bug feedback) do
        hits = for group <- search(team, word, who), hit <- group.hits, do: hit
        assert hit = Enum.find(hits, &(&1.title == "Get help")), "#{word} as #{inspect(who)}"
        assert hit.path == "/teams/#{team.subdomain}/help"
      end
    end

    test "contacts finds Team admins for team admins, where the team contacts are picked" do
      team = team_fixture()

      assert [%{kind: :page, hits: [%{title: "Team admins", path: path}]}] =
               search(team, "contacts", team_admin?: true, member?: false)

      assert path == "/teams/#{team.subdomain}/settings/team-admins"

      assert search(team, "contacts", team_admin?: false, member?: true) == []
    end

    test "admin and report don't find it" do
      team = team_fixture()

      for word <- ~w(admin report),
          group <- search(team, word, team_admin?: true, member?: false),
          hit <- group.hits do
        refute hit.title == "Get help"
      end
    end
  end

  describe "chores" do
    setup do
      team = team_fixture()
      member = member_fixture(team, %{name: "Sam Rivera"})
      chore = chore_fixture(member, chore_category_fixture(team), %{description: "Truck wash"})
      %{team: team, chore: chore}
    end

    test "a team admin finds a chore by its words on a team with chores on", ctx do
      team =
        ctx.team
        |> Ecto.Changeset.change(member_logins: true, chores_enabled: true)
        |> Repo.update!()

      assert [%{kind: :chore, hits: [hit]}] =
               search(team, "wash", team_admin?: true, member?: false)

      assert hit.path == "/teams/#{team.subdomain}/chores/#{ctx.chore.id}"
      assert hit.member_name == "Sam Rivera"

      assert search(team, "wash", team_admin?: false, member?: true) == []
    end

    test "chores aren't found on a team with chores off", %{team: team} do
      assert search(team, "wash", team_admin?: true, member?: false) == []
      refute :chore in Web.Search.kinds(team, true, false)
    end
  end

  describe "recent/3" do
    test "the picks this person can still open, newest first, from untrusted keys" do
      team = team_fixture()
      member = member_fixture(team, %{name: "Ali Here"})
      activity = activity_fixture(team, %{title: "Rope night"})

      keys = [
        "activity:#{activity.id}",
        "member:#{member.id}",
        "page:members",
        "member:x",
        "evil:1",
        "member",
        7
      ]

      admin = recent(team, keys, team_admin?: true, member?: false)

      assert [%{kind: :recent, hits: hits}] = admin
      assert Enum.map(hits, & &1.title) == ["Rope night", "Ali Here", "Members"]
      assert hd(hits).path == "/teams/#{team.subdomain}/activities/#{activity.id}"

      assert [%{hits: hits}] = recent(team, keys, team_admin?: false, member?: true)
      assert Enum.map(hits, & &1.title) == ["Rope night", "Ali Here", "Members"]

      assert recent(team, "not a list", team_admin?: true, member?: false) == []
    end
  end

  test "an All link opens the list with the search in place" do
    team = team_fixture()

    assert Web.Search.more_path(:member, team, "ali w") ==
             "/teams/#{team.subdomain}/members?q=ali+w&standing=all"

    assert Web.Search.more_path(:group, team, "x") == nil
  end

  defp recent(team, keys, who) do
    area = Navigation.area("/teams/#{team.subdomain}", team)
    sections = Navigation.sections(area, "/teams/#{team.subdomain}", who)
    Web.Search.recent(team, keys, Keyword.put(who, :sections, sections))
  end

  defp search(team, query, who) do
    area = Navigation.area("/teams/#{team.subdomain}", team)
    sections = Navigation.sections(area, "/teams/#{team.subdomain}", who)
    Web.Search.run(team, query, Keyword.merge(who, sections: sections, now: @now))
  end
end
