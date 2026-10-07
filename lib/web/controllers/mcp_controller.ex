defmodule Web.MCPController do
  @moduledoc """
  The MCP endpoint, `/teams/:subdomain/mcp` (#28): Streamable HTTP with JSON responses
  and no server-sent events, so GET and DELETE get 405. A bearer token decides the
  team, and a subdomain that isn't the token's team gets 404. Tools are in
  App.MCP.Tools and only read. See docs/mcp.md.
  """
  use Web, :controller

  alias App.MCP.Tools
  alias App.Model.MCPToken
  alias App.Operation.AuthorizeMCPRequest
  alias App.Operation.CallMCPTool

  # Newest first. The first is offered when a client asks for one not listed.
  @protocol_versions ["2025-11-25", "2025-06-18", "2025-03-26"]

  plug :check_origin
  plug :authorize
  plug :check_protocol_version

  def post(conn, _params), do: handle_message(conn, conn.assigns.mcp_token, conn.body_params)

  # No server-sent event stream and no sessions to end.
  def get(conn, _params), do: method_not_allowed(conn)
  def delete(conn, _params), do: method_not_allowed(conn)

  defp method_not_allowed(conn) do
    conn
    |> put_resp_header("allow", "POST")
    |> send_resp(405, "")
  end

  # A browser page on another site must not reach the endpoint (DNS rebinding). Agents
  # send no Origin.
  defp check_origin(conn, _opts) do
    case get_req_header(conn, "origin") do
      [] ->
        conn

      [origin | _] ->
        if URI.parse(origin).host == conn.host,
          do: conn,
          else: conn |> send_json_error(403, "Origin not allowed") |> halt()
    end
  end

  defp authorize(conn, _opts) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, %MCPToken{} = record} <- AuthorizeMCPRequest.call(token) do
      if record.team.subdomain == conn.path_params["subdomain"] do
        assign(conn, :mcp_token, record)
      else
        conn |> send_json_error(404, "Not found") |> halt()
      end
    else
      _error ->
        conn
        |> put_resp_header("www-authenticate", ~s(Bearer error="invalid_token"))
        |> send_json_error(401, "Send a live MCP token as Authorization: Bearer <token>.")
        |> halt()
    end
  end

  defp bearer_token(conn) do
    with [header | _] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(header, " ", parts: 2),
         "bearer" <- String.downcase(scheme) do
      {:ok, String.trim(token)}
    else
      _missing -> :error
    end
  end

  # After initialize, clients send the version they agreed on with every request.
  defp check_protocol_version(conn, _opts) do
    case get_req_header(conn, "mcp-protocol-version") do
      [] ->
        conn

      [version | _] when version in @protocol_versions ->
        conn

      [version | _] ->
        conn |> send_json_error(400, "Unsupported MCP-Protocol-Version: #{version}") |> halt()
    end
  end

  # Batches were dropped from MCP in 2025-06-18.
  defp handle_message(conn, _token, %{"_json" => list}) when is_list(list) do
    rpc_error(conn, 400, nil, -32_600, "Batches are not supported")
  end

  defp handle_message(conn, token, %{"jsonrpc" => "2.0", "method" => method, "id" => id} = body)
       when is_binary(method) do
    case dispatch(token, method, Map.get(body, "params") || %{}) do
      {:ok, result} -> json(conn, %{"jsonrpc" => "2.0", "id" => id, "result" => result})
      {:error, code, message} -> rpc_error(conn, 200, id, code, message)
    end
  end

  # Notifications, such as notifications/initialized, and responses to us: nothing to say.
  defp handle_message(conn, _token, %{"jsonrpc" => "2.0", "method" => method})
       when is_binary(method),
       do: send_resp(conn, 202, "")

  defp handle_message(conn, _token, %{"jsonrpc" => "2.0", "id" => _id} = body)
       when is_map_key(body, "result") or is_map_key(body, "error"),
       do: send_resp(conn, 202, "")

  defp handle_message(conn, _token, _body) do
    rpc_error(conn, 400, nil, -32_600, "Send one JSON-RPC 2.0 message")
  end

  defp dispatch(token, "initialize", params) do
    requested = params["protocolVersion"]
    version = if requested in @protocol_versions, do: requested, else: hd(@protocol_versions)
    team = token.team

    {:ok,
     %{
       "protocolVersion" => version,
       "capabilities" => %{"tools" => %{"listChanged" => false}},
       "serverInfo" => %{"name" => "sarduty", "title" => "SAR Duty", "version" => "1.0.0"},
       "instructions" =>
         "Data for #{team.name}, copied from D4H by SAR Duty. Times are in " <>
           "#{team.timezone}. Nothing here changes D4H. propose_attendance_changes saves " <>
           "a proposal that a team admin reviews and sends in SAR Duty."
     }}
  end

  defp dispatch(_token, "ping", _params), do: {:ok, %{}}

  defp dispatch(_token, "tools/list", _params), do: {:ok, %{"tools" => Tools.definitions()}}

  defp dispatch(token, "tools/call", params) when is_map(params) do
    case CallMCPTool.call(token, params["name"], params["arguments"]) do
      {:ok, output} ->
        {:ok, %{"content" => [text(Jason.encode!(output))], "isError" => false}}

      {:error, :unknown_tool} ->
        {:error, -32_602, "Unknown tool: #{inspect(params["name"])}"}

      {:error, message} ->
        {:ok, %{"content" => [text(message)], "isError" => true}}
    end
  end

  defp dispatch(_token, method, _params), do: {:error, -32_601, "Method not found: #{method}"}

  defp text(text), do: %{"type" => "text", "text" => text}

  defp rpc_error(conn, status, id, code, message) do
    conn
    |> put_status(status)
    |> json(%{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}})
  end

  defp send_json_error(conn, status, message) do
    conn |> put_status(status) |> json(%{"error" => message})
  end
end
