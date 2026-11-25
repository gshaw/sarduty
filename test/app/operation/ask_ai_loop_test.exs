defmodule App.Operation.AskAILoopTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.AI.ReportJob
  alias App.Operation.AskAI
  alias App.Operation.SetAISettings

  @now ~U[2026-11-24 18:00:00.000000Z]

  setup do
    admin = make_admin(AccountsFixtures.user_fixture())
    {:ok, _settings} = SetAISettings.call(%{access: "everyone", monthly_budget: "50"}, admin)
    :ok
  end

  # Two of South Fraser's asks (2026-11-24) checked a passing query until requests ran out.
  test "a Claude that keeps checking answers on the last request, which can't call a tool" do
    %{user: user, team: team} = user_with_team_fixture()
    job = stub_claude(team, "select name, standing from members")

    assert {:ok, %{query: "select name, standing from members"}} =
             AskAI.call(team, user, job, @now)

    for _n <- 1..5, do: assert_received({:claude, nil})
    assert_received {:claude, %{"type" => "none"}}
    refute_received {:claude, _choice}
  end

  test "a mistake in the last request's answer shows, with no request left to fix it" do
    %{user: user, team: team} = user_with_team_fixture()
    job = stub_claude(team, "select nope from members")

    assert {:error, {:checks, _mistake}} = AskAI.call(team, user, job, @now)
    for _n <- 1..5, do: assert_received({:claude, nil})
    assert_received {:claude, %{"type" => "none"}}
    refute_received {:claude, _choice}
  end

  defp stub_claude(team, answer) do
    test = self()

    Req.Test.stub(App.Adapter.Claude, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      send(test, {:claude, request["tool_choice"]})

      Req.Test.json(conn, response(request["tool_choice"], answer))
    end)

    report = %{query: "select name from members", name: "Members", about: "Every member."}
    ReportJob.build(team, report, "add standing", @now)
  end

  defp response(%{"type" => "none"}, answer) do
    output = %{
      "query" => answer,
      "name" => "",
      "about" => "",
      "note" => "Added standing."
    }

    %{
      "stop_reason" => "end_turn",
      "content" => [%{"type" => "text", "text" => Jason.encode!(output)}],
      "usage" => %{"input_tokens" => 900, "output_tokens" => 100}
    }
  end

  defp response(nil, _answer) do
    %{
      "stop_reason" => "tool_use",
      "content" => [
        %{
          "type" => "tool_use",
          "id" => "c#{System.unique_integer([:positive])}",
          "name" => "check_report",
          "input" => %{"query" => "select name, standing from members"}
        }
      ],
      "usage" => %{"input_tokens" => 900, "output_tokens" => 100}
    }
  end
end
