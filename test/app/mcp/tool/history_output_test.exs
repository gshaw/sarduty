defmodule App.MCP.Tool.HistoryOutputTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.HistoryOutput

  test "leaves out standing changes, whose away reasons are personal (#366)" do
    entries = [
      %{
        at: ~U[2026-10-02 18:00:00Z],
        seen_after: nil,
        by: :team_admin,
        kind: :standing,
        text: "Away period added: Parental leave, Sep 8, 2026 to Mar 1, 2027"
      },
      %{
        at: ~U[2026-10-01 18:00:00Z],
        seen_after: ~U[2026-10-01 17:50:00Z],
        by: :d4h,
        kind: :member,
        text: "Position changed from MIT to Member"
      }
    ]

    assert [%{"change" => "Position changed from MIT to Member", "by" => "d4h"}] =
             HistoryOutput.build(entries, "America/Vancouver")
  end
end
