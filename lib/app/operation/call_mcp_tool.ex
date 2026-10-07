defmodule App.Operation.CallMCPTool do
  @moduledoc """
  Runs one MCP tool for an authorized token, on the token's team, and logs the call
  (#28). Every call is logged, an unknown tool or a failed one included.
  """

  alias App.MCP.Tools
  alias App.Model.MCPCall
  alias App.Model.MCPToken

  @doc """
  `{:ok, output}`, `{:error, message}` for the agent to read, or `{:error, :unknown_tool}`.
  """
  def call(%MCPToken{} = token, name, args, now \\ DateTime.utc_now()) do
    args = if is_map(args), do: args, else: %{}
    started = System.monotonic_time(:millisecond)

    case Tools.find(name) do
      nil ->
        record!(token, tool_name(name), %{}, started, error: "Unknown tool")
        {:error, :unknown_tool}

      tool ->
        logged_args = Tools.loggable_arguments(tool, args)

        try do
          tool.call(token.team, args, now)
        rescue
          exception ->
            record!(token, name, logged_args, started, error: "Crashed")
            reraise exception, __STACKTRACE__
        else
          {:ok, output, rows} ->
            record!(token, name, logged_args, started, row_count: rows)
            {:ok, output}

          {:error, message} ->
            record!(token, name, logged_args, started, error: message)
            {:error, message}
        end
    end
  end

  defp tool_name(name) when is_binary(name), do: name
  defp tool_name(_name), do: "(none)"

  defp record!(token, tool, args, started, result) do
    MCPCall.record!(
      token: token,
      tool: tool,
      arguments: args,
      row_count: result[:row_count],
      error: result[:error],
      duration_ms: System.monotonic_time(:millisecond) - started
    )
  end
end
