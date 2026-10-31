defmodule App.Operation.AuthorizeAgent do
  @moduledoc """
  The Allow step of connecting an AI agent (#761): `/teams/:subdomain/oauth/authorize`.
  `check/3` reads the agent's request; `allow/4` writes the connection with a code and
  says where to send the admin back. Only a user who passes `Team.managed_by?/3` may
  allow, on a team with Agents on. See docs/mcp.md.
  """

  alias App.Accounts.User
  alias App.Model.AgentClient
  alias App.Model.AgentConnection
  alias App.Model.Event
  alias App.Model.Team
  alias App.Repo

  @code_minutes 10

  @doc """
  Reads an authorize request against the agent's registration, `nil` when its client
  id is unknown. Pure. `mcp_url` is the team's MCP address, which `resource` must name
  when sent.

  - `{:ok, request}`: may be allowed. `request` has `client`, `name`, `redirect_uri`,
    `state`, and `code_challenge`.
  - `{:unknown_agent, host}`: a web agent not on SAR Duty's list.
  - `{:redirect, url}`: a bad request from a known agent, sent back to it with the error.
  - `{:bad_link, message}`: nowhere safe to send the admin back to.
  """
  def check(params, client, mcp_url) do
    with {:ok, client} <- known_client(client),
         {:ok, uri} <- registered_redirect(params["redirect_uri"], client) do
      case AgentClient.redirect_kind(uri) do
        {:unknown, host} -> {:unknown_agent, host}
        :invalid -> {:bad_link, "This agent’s return address is not one SAR Duty accepts."}
        _known -> check_request(params, client, uri, mcp_url)
      end
    end
  end

  defp known_client(nil), do: {:bad_link, "SAR Duty does not know this agent. Connect again."}
  defp known_client(client), do: {:ok, client}

  # An agent registered with one address may leave it out (RFC 6749 section 3.1.2.3).
  defp registered_redirect(nil, %AgentClient{redirect_uris: [uri]}), do: {:ok, uri}

  defp registered_redirect(uri, client) do
    if uri in client.redirect_uris,
      do: {:ok, uri},
      else: {:bad_link, "This agent sent a return address it did not register."}
  end

  defp check_request(params, client, uri, mcp_url) do
    state = params["state"]

    cond do
      params["response_type"] != "code" ->
        {:redirect, error_url(uri, state, "unsupported_response_type")}

      not valid_challenge?(params["code_challenge"]) or
          params["code_challenge_method"] != "S256" ->
        {:redirect, error_url(uri, state, "invalid_request", "PKCE with S256 is required.")}

      not resource_ok?(params["resource"], mcp_url) ->
        {:redirect, error_url(uri, state, "invalid_target", "Use this team’s MCP address.")}

      true ->
        {:ok,
         %{
           client: client,
           name: AgentClient.display_name(client, uri),
           redirect_uri: uri,
           state: state,
           code_challenge: params["code_challenge"]
         }}
    end
  end

  # RFC 7636: 43 to 128 characters of base64url.
  defp valid_challenge?(challenge) when is_binary(challenge),
    do: String.match?(challenge, ~r/\A[A-Za-z0-9_~.-]{43,128}\z/)

  defp valid_challenge?(_challenge), do: false

  @doc "Whether `resource`, when sent, names the team's MCP address. Pure."
  def resource_ok?(nil, _mcp_url), do: true

  def resource_ok?(resource, mcp_url) when is_binary(resource),
    do: String.trim_trailing(resource, "/") == mcp_url

  def resource_ok?(_resource, _mcp_url), do: false

  @doc """
  Allows the agent: `{:ok, url}` to send the admin back to with a code, or `{:error,
  :not_allowed}` for someone who isn't a team admin. Records the connection event,
  which notes the Allow page showed its warning.
  """
  def allow(%Team{} = team, %User{} = user, request, now \\ DateTime.utc_now()) do
    if team.mcp_enabled and Team.managed_by?(team, user.email, now) do
      code = AgentConnection.new_secret(:code)

      {:ok, _connection} =
        Repo.transaction(fn ->
          connection =
            Repo.insert!(%AgentConnection{
              team_id: team.id,
              user_id: user.id,
              agent_client_id: request.client.id,
              name: request.name,
              redirect_uri: request.redirect_uri,
              code_hash: AgentConnection.hash(code),
              code_challenge: request.code_challenge,
              code_expires_at: DateTime.add(now, @code_minutes, :minute)
            })

          Event.record!(:agent_connected,
            team_id: team.id,
            user_id: user.id,
            data: %{agent_connection_id: connection.id, warning_shown: true}
          )

          connection
        end)

      {:ok, redirect_url(request.redirect_uri, code: code, state: request.state)}
    else
      {:error, :not_allowed}
    end
  end

  @doc "Where Cancel and Back to the agent go: its return address with access denied."
  def deny_url(request), do: error_url(request.redirect_uri, request.state, "access_denied")

  defp error_url(uri, state, error, description \\ nil) do
    redirect_url(uri, error: error, error_description: description, state: state)
  end

  defp redirect_url(uri, params) do
    parsed = URI.parse(uri)
    added = for {key, value} <- params, value != nil, into: %{}, do: {to_string(key), value}
    query = (parsed.query || "") |> URI.decode_query() |> Map.merge(added)
    URI.to_string(%{parsed | query: URI.encode_query(query)})
  end
end
