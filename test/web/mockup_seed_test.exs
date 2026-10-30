defmodule Web.MockupSeedTest do
  # The mockup kit (docs/mockups.md) draws on pages this seed dumps. When a fixture or a
  # page changes under it, this fails here instead of in the next round of mockups.
  use Web.ConnCase, async: true

  # cspell:ignore Priya

  alias Web.MockupSeed

  @tag :tmp_dir
  test "seeds the cast and dumps a page", %{tmp_dir: dir} do
    cast = MockupSeed.team()

    MockupSeed.dump(
      [
        {"account", MockupSeed.conn_for(cast.cameron), ~p"/account"},
        {"members", MockupSeed.conn_for(cast.alex), ~p"/teams/coastrange/members"}
      ],
      dir
    )

    assert dir |> Path.join("account.html") |> File.read!() =~ "Coast Range SAR"
    assert dir |> Path.join("members.html") |> File.read!() =~ "Priya Nair"
  end
end
