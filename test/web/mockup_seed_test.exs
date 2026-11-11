defmodule Web.MockupSeedTest do
  # The mockup kit (docs/mockups.md) draws on pages this seed dumps. When a fixture or a
  # page changes under it, this fails here instead of in the next round of mockups.
  # Not async: the cast is about 1,100 rows, and their insert holds SQLite's write lock,
  # which every async test's sandbox waits on.
  use Web.ConnCase, async: false

  # cspell:ignore Priya

  import Ecto.Query, only: [where: 3]

  alias Web.MockupSeed

  @tag :tmp_dir
  test "seeds the cast and dumps a page", %{tmp_dir: dir} do
    cast = MockupSeed.team()
    hiker = MockupSeed.activity(cast, "Missing hiker")

    MockupSeed.dump(
      [
        {"account", MockupSeed.conn_for(cast.cameron), ~p"/account"},
        {"members", MockupSeed.conn_for(cast.alex), ~p"/teams/coastrange/members"},
        {"activity", MockupSeed.conn_for(cast.alex), ~p"/teams/coastrange/activities/#{hiker.id}"}
      ],
      dir
    )

    assert dir |> Path.join("account.html") |> File.read!() =~ "Coast Range SAR"
    assert dir |> Path.join("members.html") |> File.read!() =~ "Priya Nair"
    assert dir |> Path.join("activity.html") |> File.read!() =~ "Missing hiker"
  end

  # One cast: the mockups' team is the team agents' reports run on.
  test "the cast is Coast Range SAR's, in the test database and the sample one" do
    cast = MockupSeed.team()
    names = for {name, %App.Model.Member{}} <- cast, do: name

    assert Enum.sort(names) == Enum.sort(App.CoastRange.names())

    # The sample database has Silver Basin SAR beside it (#963).
    sample = App.SampleRepo.team()

    for schema <- [App.Model.Member, App.Model.Activity, App.Model.EquipmentItem] do
      in_sample =
        schema |> where([r], r.team_id == ^sample.id) |> App.SampleRepo.aggregate(:count)

      assert App.Repo.aggregate(schema, :count) == in_sample
    end
  end
end
