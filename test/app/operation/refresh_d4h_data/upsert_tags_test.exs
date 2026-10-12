defmodule App.Operation.RefreshD4HData.UpsertTagsTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.Kit
  alias App.Model.KitTag
  alias App.Model.Tag
  alias App.Operation.RefreshD4HData.UpsertTags

  @now ~U[2026-10-12 12:00:00.000000Z]

  test "keeps a copy of the team's tags, renames them, and deletes the ones D4H dropped" do
    team = team_fixture()
    other = tag_fixture(team_fixture(), "Other team")

    UpsertTags.save(team.id, [%D4H.Tag{d4h_tag_id: 1, title: "Boat"}], @now)
    boat = Repo.get_by!(Tag, team_id: team.id, d4h_tag_id: 1)
    kit = kit_fixture(team, "Boat", [], [boat])

    UpsertTags.save(
      team.id,
      [%D4H.Tag{d4h_tag_id: 2, title: "Flat Water"}, %D4H.Tag{d4h_tag_id: 1, title: "Boats"}],
      @now
    )

    assert team.id |> Tag.get_all() |> Enum.map(&{&1.d4h_tag_id, &1.title}) ==
             [{1, "Boats"}, {2, "Flat Water"}]

    UpsertTags.save(team.id, [%D4H.Tag{d4h_tag_id: 2, title: "Flat Water"}], @now)

    refute Repo.get(Tag, boat.id)
    assert Repo.get(Kit, kit.id)
    assert Repo.all(KitTag) == []
    assert Repo.get(Tag, other.id)
  end
end
