defmodule Web.Mockups.ExampleDumpTest do
  # The kit's example round (docs/mockups.md): the real pages it draws on. Never run by
  # `mix test`; tools/mockups/dump.sh copies it into test/mockups/ for one run.
  use Web.ConnCase

  alias Web.MockupSeed

  test "dump" do
    cast = MockupSeed.team()

    MockupSeed.dump([
      {"account", MockupSeed.conn_for(cast.cameron), ~p"/account"}
    ])
  end
end
