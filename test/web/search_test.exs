defmodule Web.SearchTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias Web.Components.TeamSettingsTabs
  alias Web.Navigation

  @now ~U[2026-10-23 19:00:00Z]

  # A new page for one record fails here until search finds its kind, or not_searched/0
  # says why it doesn't (#473).
  test "every team page for one record is searched or says why not" do
    record_pages =
      for %{path: path, metadata: %{phoenix_live_view: {view, _action, _opts, _extra}}} <-
            Web.Router.__routes__(),
          String.starts_with?(path, "/teams/:subdomain/"),
          path =~ ~r{/:(\w+_)?id$},
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

    test "a letter's ID opens the member's letter for its year (#970)", %{team: team} do
      member = member_fixture(team)
      letter = tax_credit_letter_fixture(member, %{year: 2025, code: "K7Q4M2XA9HVB3TN"})

      assert [%{kind: :document, hits: [hit]}] =
               search(team, "K7Q4M-2XA9H", team_admin?: true, member?: false)

      assert hit.id == letter.id
      assert hit.path == "/teams/#{team.subdomain}/tax-credit-letters/2025/members/#{member.id}"
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

    test "admin and report don't find it" do
      team = team_fixture()

      for word <- ~w(admin report),
          group <- search(team, word, team_admin?: true, member?: false),
          hit <- group.hits do
        refute hit.title == "Get help"
      end
    end
  end

  describe "pages" do
    @admin [team_admin?: true, member?: false]
    @member [team_admin?: false, member?: true]

    test "a team admin finds each Team settings tab by its name, under Team settings" do
      team =
        team_fixture()
        |> Ecto.Changeset.change(member_logins: true, chores_enabled: true, mcp_enabled: true)
        |> Repo.update!()

      for tab <- TeamSettingsTabs.list(team), tab.key != :general do
        hit = page_hit(team, tab.label, @admin, tab.path)
        assert hit, "#{tab.label} isn't found"
        assert hit.line == "Team settings"
      end

      # The tab and the side navigation's Members page are both found, the page first.
      pages = team |> search("members", @admin) |> Enum.filter(&(&1.kind == :page))
      assert [%{hits: [%{title: "Members", path: members}, %{title: "Members"} | _rest]}] = pages

      assert members == "/teams/#{team.subdomain}/members"
    end

    test "Chore categories and Agents are found only when their tabs show" do
      team = team_fixture()

      refute page_hit(
               team,
               "chore categories",
               @admin,
               "/teams/#{team.subdomain}/settings/chore-categories"
             )

      refute page_hit(team, "agents", @admin, "/teams/#{team.subdomain}/settings/mcp")
    end

    # A Change page is a step from General, so its words find General (docs/search.md).
    test "a Change page's words find Team settings, never the Change page" do
      team = team_fixture()
      settings = "/teams/#{team.subdomain}/settings"

      for words <- [
            "logo",
            "access key",
            "time zone",
            "contacts",
            "team contacts",
            "address",
            "legal name",
            "token"
          ] do
        assert page_hit(team, words, @admin, settings), "#{words} doesn't find Team settings"
      end

      steps = for step <- ~w(edit logo contacts access-key), do: "#{settings}/#{step}"

      for words <- ["change", "change team", "change logo", "logo", "contacts", "access key"],
          group <- search(team, words, @admin),
          hit <- group.hits do
        refute hit.path in steps, "#{words} found #{hit.path}"
      end
    end

    test "everyone finds Account settings by what it holds, not by reminders" do
      team = team_fixture()

      for who <- [@admin, @member],
          words <- ["account", "account settings", "passkey", "maps", "apple", "emails"] do
        assert page_hit(team, words, who, "/account"), "#{words} doesn't find Account settings"
      end

      refute page_hit(team, "reminders", @admin, "/account")
    end

    test "a member finds no Team settings tab" do
      team = team_fixture()

      for words <- ["admins", "features", "signer", "places", "logo", "access key", "time zone"],
          group <- search(team, words, @member),
          hit <- group.hits do
        refute String.contains?(hit.path, "/settings"), "#{words} found #{hit.path}"
      end
    end

    test "a member finds Your membership by what it shows and Change contact details" do
      team = team_fixture()
      me = "/teams/#{team.subdomain}/me"

      for words <- [
            "card",
            "id card",
            "phone",
            "mobile",
            "address",
            "emergency contacts",
            "contact details"
          ] do
        assert page_hit(team, words, @member, me), "#{words} doesn't find Your membership"
      end

      refute page_hit(team, "card", @admin, me)
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

  defp page_hit(team, query, who, path) do
    team
    |> search(query, who)
    |> Enum.find_value(fn group ->
      group.kind == :page && Enum.find(group.hits, &(&1.path == path))
    end)
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
