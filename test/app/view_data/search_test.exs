defmodule App.ViewData.SearchTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.ViewData.Search

  @now ~U[2026-10-23 19:00:00Z]

  describe "terms/1" do
    test "lowercases, splits on spaces, and drops a leading #" do
      assert Search.terms("  Rope  #02193 ") == ["rope", "02193"]
    end

    test "a blank search or a lone # has no words" do
      assert Search.terms("   ") == []
      assert Search.terms("#") == []
      assert Search.terms(nil) == []
    end

    test "keeps at most 6 words" do
      assert length(Search.terms("a b c d e f g h")) == 6
    end
  end

  describe "score/3" do
    test "a key that is the whole search beats any title, with or without leading zeros" do
      assert Search.score("Training night", ["02193"], ["02193"]) == 100
      assert Search.score("Training night", ["02193"], ["2193"]) == 100
      assert Search.score("Training night", ["R1"], ["r1"]) == 100
    end

    test "exact, then starts with, then word starts, then anywhere" do
      assert Search.score("Rope team", [], ["rope", "team"]) == 90
      assert Search.score("Rope rescue refresher", [], ["rope", "res"]) == 80
      assert Search.score("Technical rope rescue", [], ["rescue", "rope"]) == 60
      assert Search.score("Natalie Brooks", [], ["ali"]) == 40
      assert Search.score("Natalie Brooks", ["M12"], ["m12", "ali"]) == 20
    end

    test "matches word starts after punctuation" do
      assert Search.score("Navigation day, Alice Lake", [], ["alice"]) == 60
    end
  end

  describe "rank/3" do
    test "groups go best hit first, ties in kind order, and each keeps 5" do
      members = for n <- 1..7, do: member_hit(n, "Alice #{n}")
      activities = [activity_hit(1, "Alice", @now)]

      [first, second] =
        Search.rank([member: members, activity: activities], ["alice"], @now)

      assert first.kind == :activity
      assert hd(first.hits).score == 90
      assert second.kind == :member
      assert length(second.hits) == 5
      assert second.more?
    end

    test "kinds tie in kinds/0 order" do
      groups =
        Search.rank(
          [group: [%{id: 1, title: "Rope"}], member: [member_hit(1, "Rope")]],
          ["rope"],
          @now
        )

      assert Enum.map(groups, & &1.kind) == [:member, :group]
    end

    test "retired members go after current ones with the same score" do
      hits = [member_hit(1, "Sam Lee", :retired), member_hit(2, "Sam Ito")]
      [%{hits: [first, second]}] = Search.rank([member: hits], ["sam"], @now)
      assert {first.id, second.id} == {2, 1}
    end

    test "activities nearest now go first" do
      hits = [
        activity_hit(1, "Rope night", DateTime.add(@now, -400, :day)),
        activity_hit(2, "Rope night", DateTime.add(@now, 3, :day)),
        activity_hit(3, "Rope night", DateTime.add(@now, -20, :day))
      ]

      [%{hits: ranked}] = Search.rank([activity: hits], ["rope"], @now)
      assert Enum.map(ranked, & &1.id) == [2, 3, 1]
    end

    test "a kind with nothing found is left out" do
      assert Search.rank([member: [], group: []], ["x"], @now) == []
    end
  end

  describe "run/3" do
    setup do
      %{team: team_fixture(), other: team_fixture()}
    end

    test "every word must match, in any order, on the team only", %{team: team, other: other} do
      member_fixture(team, %{name: "John Smith"})
      member_fixture(team, %{name: "John Brown"})
      member_fixture(other, %{name: "John Smith"})

      assert [%{kind: :member, hits: [%{title: "John Smith"}]}] =
               Search.run(team, "smith john", kinds: [:member], now: @now)
    end

    test "finds an activity by its D4H number and leaves out deleted ones", %{team: team} do
      activity_fixture(team, %{title: "Rope night", ref_id: "02193"})
      activity_fixture(team, %{title: "Rope day", deleted_at: @now})

      assert [%{hits: [%{title: "Rope night", score: 100}]}] =
               Search.run(team, "#2193", kinds: [:activity], now: @now)

      assert [%{hits: [%{title: "Rope night"}]}] =
               Search.run(team, "rope", kinds: [:activity], now: @now)
    end

    test "finds equipment by barcode and says whether it is in service", %{team: team} do
      equipment_item_fixture(team, %{title: "Rescue truck", barcode: "R1"})
      equipment_item_fixture(team, %{title: "Old truck", status: "retired"})

      assert [%{hits: [%{title: "Rescue truck", in_service?: true}]}] =
               Search.run(team, "r1", kinds: [:equipment], now: @now)

      assert [%{hits: [%{in_service?: true}, %{title: "Old truck", in_service?: false}]}] =
               Search.run(team, "truck", kinds: [:equipment], now: @now)
    end

    test "% and _ match themselves", %{team: team} do
      qualification_fixture(team, %{title: "First aid"})
      qualification_fixture(team, %{title: "100% fit"})

      assert [%{hits: [%{title: "100% fit"}]}] =
               Search.run(team, "0%", kinds: [:qualification], now: @now)

      assert Search.run(team, "_", kinds: [:qualification], now: @now) == []
    end

    test "says each member's standing", %{team: team} do
      away = member_fixture(team, %{name: "Ali Away"})
      away_period_fixture(away, ~D[2026-10-01], ~D[2026-11-03])
      member_fixture(team, %{name: "Ali Gone", d4h_status: "RETIRED"})
      member_fixture(team, %{name: "Ali Here"})

      [%{hits: hits}] = Search.run(team, "ali", kinds: [:member], now: @now)

      assert Map.new(hits, &{&1.title, &1.standing}) == %{
               "Ali Away" => {:away, ~D[2026-11-03]},
               "Ali Gone" => :retired,
               "Ali Here" => :active
             }
    end

    test "searches only the kinds asked for, and pages by title", %{team: team} do
      group_fixture(team, %{title: "Tax team"})
      template_fixture(team, "Tax kit")
      endorsement_fixture(team, %{name: "Tax lead"})
      pages = [%{id: "tax-credit-letters", title: "Tax credit letters", path: "/x"}]

      assert [%{kind: :page, hits: [%{path: "/x"}]}] =
               Search.run(team, "tax letters", kinds: [:group, :page], pages: pages, now: @now)

      assert Search.run(team, "redit", kinds: [:page], pages: pages, now: @now) == []

      kinds =
        team
        |> Search.run("tax", kinds: [:template, :endorsement], now: @now)
        |> Enum.map(& &1.kind)

      assert Enum.sort(kinds) == [:endorsement, :template]
    end

    test "a blank search finds nothing", %{team: team} do
      member_fixture(team)
      assert Search.run(team, " ", kinds: Search.kinds(), now: @now) == []
    end
  end

  defp member_hit(id, name, standing \\ :active),
    do: %{id: id, title: name, keys: [], standing: standing}

  defp activity_hit(id, title, started_at),
    do: %{id: id, title: title, keys: [], started_at: started_at}
end
