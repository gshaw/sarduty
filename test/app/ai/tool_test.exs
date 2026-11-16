defmodule App.AI.ToolTest do
  # What each tool answers Claude (#816), moved from the MCP tests when MCP went (#1087):
  # never a record, a count, or a key outside its list, and try_report only Coast Range
  # SAR's made-up rows.
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AI.Tool.CheckReport
  alias App.AI.Tool.TryReport

  @now ~U[2026-11-15 18:00:00Z]

  # Every key each tool may answer with, at any depth.
  @keys %{
    CheckReport => ~w(ok columns),
    TryReport => ~w(team made_up names columns rows more groups qualifications tags
                    custom_fields write on)
  }

  test "no tool answer holds a record, a count, or a key outside its list" do
    team = team_fixture()

    member =
      member_fixture(team, %{
        name: "Pat Example",
        ref_id: "4471",
        email: "pat.secret@example.com",
        phone: "604-555-0199",
        address: "42 Hidden Road"
      })

    group_member_fixture(group_fixture(team, %{title: "Callout"}), member)

    activity =
      activity_fixture(team, %{
        title: "Search for the lost hiker",
        started_at: ~U[2026-03-01 17:00:00Z],
        finished_at: ~U[2026-03-01 20:00:00Z],
        address: "99 Trailhead Way",
        description: "Meet at the gate",
        tracking_number: "PROS-2026-99881"
      })

    attendance_fixture(activity, member, %{
      started_at: ~U[2026-03-01 17:00:00Z],
      finished_at: ~U[2026-03-01 20:00:00Z]
    })

    tax_credit_letter_fixture(member, %{letter_content: "Dear Pat, private letter text"})

    secrets = [
      "Pat Example",
      "4471",
      "pat.secret@example.com",
      "604-555-0199",
      "42 Hidden Road",
      "Search for the lost hiker",
      "99 Trailhead Way",
      "Meet at the gate",
      "PROS-2026-99881",
      "private letter text",
      team.mailing_address
    ]

    calls = [
      {CheckReport, %{"query" => "select name, ref_id, email, mobile, address from members"}},
      {CheckReport, %{"query" => "select title, address, tracking_number from activities"}},
      {TryReport, %{"query" => "select name, ref_id, email, mobile, address from members"}},
      {TryReport, %{"query" => "select title, address, tracking_number from activities"}}
    ]

    for {tool, args} <- calls do
      assert {:ok, output} = tool.call(%{team: team, now: @now}, args)
      text = Jason.encode!(output)

      for key <- keys(output) do
        assert key in @keys[tool], "#{tool.name()} answered with #{key}, which isn't in its list"
      end

      for secret <- secrets, do: refute(text =~ secret, "#{tool.name()} answered #{secret}")
    end
  end

  test "check_report gives the columns without running the query" do
    team = team_fixture()
    member_fixture(team, %{name: "Pat Example"})

    assert CheckReport.call(%{team: team, now: @now}, %{
             "query" => "select name, last_attended from members"
           }) == {:ok, %{"ok" => true, "columns" => ["Member", "Last attended"]}}

    assert {:error, message} =
             CheckReport.call(%{team: team, now: @now}, %{"query" => "select nme from members"})

    assert message =~ "members has no field nme"
  end

  test "try_report runs on Coast Range SAR, never the team's records" do
    team = team_fixture()
    member_fixture(team, %{name: "Pat Example"})
    context = %{team: team, now: @now}

    query = "select name, standing from members where name = 'Cameron Ruiz'"
    assert {:ok, output} = TryReport.call(context, %{"query" => query})

    assert output["team"] == "Coast Range SAR"
    assert output["made_up"]
    assert output["columns"] == ["Member", "Standing"]
    assert [["Cameron Ruiz", _standing]] = output["rows"]
    assert "Search manager" in output["names"]["qualifications"]
    assert "Rope team" in output["names"]["groups"]
    assert "Swiftwater" in output["names"]["tags"]
    assert %{"write" => "`Task Type`", "on" => "activities"} in output["names"]["custom_fields"]
    refute Jason.encode!(output) =~ "Pat Example"

    # A year sent as a JSON number picks that year, not this one.
    query = "select title from activities where year(started_at) = :year"

    assert {:ok, output} =
             TryReport.call(context, %{"query" => query, "values" => %{"year" => 1999}})

    assert output["rows"] == []

    assert {:error, message} = TryReport.call(context, %{"query" => "select nme from members"})
    assert message =~ "members has no field nme"
  end

  defp keys(map) when is_map(map),
    do: Enum.flat_map(map, fn {key, value} -> [key | keys(value)] end)

  defp keys(list) when is_list(list), do: Enum.flat_map(list, &keys/1)
  defp keys(_value), do: []
end
