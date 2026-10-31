defmodule Web.MCPController do
  @moduledoc """
  The MCP endpoint, `/teams/:subdomain/mcp` (#28): Streamable HTTP with JSON responses
  and no server-sent events, so GET and DELETE get 405. An agent's access token (#761)
  decides the team, and a subdomain that isn't the token's team gets 404. With no
  token, or a bad one, the 401 points the agent to the team's OAuth metadata
  (Web.OAuthController). Tools are in App.MCP.Tools and only read. See docs/mcp.md.
  """
  use Web, :controller

  alias App.Adapter.D4H
  alias App.MCP.Tools
  alias App.Model.AgentConnection
  alias App.Operation.AuthorizeMCPRequest
  alias App.Operation.CallMCPTool

  # Newest first. The first is offered when a client asks for one not listed.
  @protocol_versions ["2025-11-25", "2025-06-18", "2025-03-26"]

  plug :check_origin
  plug :authorize
  plug :check_protocol_version

  def post(conn, _params),
    do: handle_message(conn, conn.assigns.agent_connection, conn.body_params)

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
    sent = bearer_token(conn)

    with {:ok, token} <- sent,
         {:ok, %AgentConnection{} = connection} <- AuthorizeMCPRequest.call(token) do
      if connection.team.subdomain == conn.path_params["subdomain"] do
        assign(conn, :agent_connection, connection)
      else
        conn |> send_json_error(404, "Not found") |> halt()
      end
    else
      _error -> conn |> unauthorized(sent) |> halt()
    end
  end

  # RFC 9728 section 5.1: where the agent finds how to get a token. A sent token that
  # failed also says so (RFC 6750 section 3.1).
  defp unauthorized(conn, sent) do
    metadata = Web.OAuthController.resource_metadata_url(conn.path_params["subdomain"])
    error = if match?({:ok, _token}, sent), do: ~s(error="invalid_token", ), else: ""

    conn
    |> put_resp_header("www-authenticate", ~s(Bearer #{error}resource_metadata="#{metadata}"))
    |> send_json_error(401, "Connect this agent from Team settings, then Agents, in SAR Duty.")
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

  defp handle_message(
         conn,
         connection,
         %{"jsonrpc" => "2.0", "method" => method, "id" => id} = body
       )
       when is_binary(method) do
    case dispatch(connection, method, Map.get(body, "params") || %{}) do
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

  defp dispatch(connection, "initialize", params) do
    requested = params["protocolVersion"]
    version = if requested in @protocol_versions, do: requested, else: hd(@protocol_versions)
    team = connection.team
    service = D4H.service_name(team)

    {:ok,
     %{
       "protocolVersion" => version,
       "capabilities" => %{"tools" => %{"listChanged" => false}},
       "serverInfo" => %{"name" => "sarduty", "title" => "SAR Duty", "version" => "1.0.0"},
       "instructions" =>
         "Data for #{team.name}, copied from #{service} by SAR Duty, up to 10 minutes " <>
           "behind. Times are in #{team.timezone}. Start with get_team. Tools only read: " <>
           "nothing here changes SAR Duty or #{service}."
     }}
  end

  defp dispatch(_connection, "ping", _params), do: {:ok, %{}}

  defp dispatch(_connection, "tools/list", _params), do: {:ok, %{"tools" => Tools.definitions()}}

  defp dispatch(connection, "tools/call", params) when is_map(params) do
    case CallMCPTool.call(connection, params["name"], params["arguments"]) do
      {:ok, output} ->
        {:ok, %{"content" => [text(Jason.encode!(output))], "isError" => false}}

      {:error, :unknown_tool} ->
        {:error, -32_602, "Unknown tool: #{inspect(params["name"])}"}

      {:error, message} ->
        {:ok, %{"content" => [text(message)], "isError" => true}}
    end
  end

  defp dispatch(_connection, method, _params),
    do: {:error, -32_601, "Method not found: #{method}"}

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
