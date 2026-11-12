defmodule App.Ops.ProdGuardTest do
  # The hook in .claude/settings.json that keeps agents on bin/prod (docs/production.md).
  use ExUnit.Case, async: true

  @hook Path.expand("../../../.claude/hooks/prod-guard", __DIR__)

  # The decision for one Bash command, as Claude Code would get it: "allow" when silent.
  defp decision(command), do: command |> hook() |> Map.get("permissionDecision", "allow")

  # The question shown with an "ask".
  defp reason(command), do: hook(command)["permissionDecisionReason"]

  defp hook(command) do
    script = ~s(printf '%s' "$1" | jq -Rs '{tool_input: {command: .}}' | "$2")
    env = for {name, _value} <- System.get_env(), name != "PATH", do: {name, nil}
    {out, 0} = System.cmd("sh", ["-c", script, "sh", command, @hook], env: env)

    case out do
      "" -> %{}
      json -> Jason.decode!(json)["hookSpecificOutput"]
    end
  end

  test "refuses raw fly ssh, fly console, machine exec, and the ssh token" do
    for command <- [
          ~s|FLY_ACCESS_TOKEN=$(fnox get FLY_SARDUTY_SSH_TOKEN) fly ssh console -a sarduty -C "x"|,
          "timeout 90 flyctl ssh console -a sarduty",
          "cd x && fly ssh sftp shell",
          "fly console -a sarduty",
          "fly machines exec 123 ls",
          "x=$(fnox get FLY_SARDUTY_SSH_TOKEN | wc -c)"
        ] do
      assert decision(command) == "deny", command
    end
  end

  test "keeps agents off bin/prod console, and asks before fix" do
    assert decision("bin/prod console --why x") == "deny"
    assert decision("/Users/someone/sarduty/bin/prod console --why x") == "deny"
    assert decision("bin/prod fix make-admin a@example.org --why x") == "ask"
  end

  test "asks in plain words, naming the task and why" do
    assert reason(~s|bin/prod fix make-admin a@example.org --why "#517 test"|) ==
             "Run make-admin in production? It changes data. Why: #517 test"

    assert reason("bin/prod fix restore-team x.db 15 --why='mistaken delete'") ==
             "Run restore-team in production? It changes data. Why: mistaken delete"
  end

  test "lets reads, deploys, logs, and text that only mentions them through" do
    for command <- [
          ~s|bin/prod query "select 1" --why "#517"|,
          ~s|bin/prod backup --why "dev copy"|,
          "bin/prod list",
          ~s|grep -rn "fly ssh" docs|,
          ~s|git commit -m "bin/prod fix make-admin"|,
          "mise run deploy",
          "fly logs -a sarduty --no-tail"
        ] do
      assert decision(command) == "allow", command
    end
  end
end
