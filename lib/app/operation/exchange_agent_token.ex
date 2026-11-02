defmodule App.Operation.ExchangeAgentToken do
  @moduledoc """
  The token endpoint for AI agents (#761), `/teams/:subdomain/oauth/token`: a code for
  an access token and a refresh token, or a refresh token for a new pair. An access
  token lives an hour. A refresh token lasts until 90 days without a refresh.

  Refreshing rotates. The refresh token it replaces still works for 60 seconds, so an
  agent whose answer got lost on the way can ask again and stay connected. Reuse after
  that is refused, not treated as theft: Disconnect is how an admin cuts a connection.
  See docs/mcp.md.
  """

  alias App.Model.AgentClient
  alias App.Model.AgentConnection
  alias App.Model.Team
  alias App.Operation.AuthorizeAgent
  alias App.Repo

  @access_seconds 3600
  @refresh_days 90
  @grace_seconds 60

  @doc """
  `{:ok, response}` with the tokens to send, or `{:error, error, description}` with an
  OAuth error code (RFC 6749 section 5.2).
  """
  def call(%Team{} = team, mcp_url, params, now \\ DateTime.utc_now()) do
    with :ok <- check_resource(params["resource"], mcp_url) do
      grant(params["grant_type"], team, params, now)
    end
  end

  defp check_resource(resource, mcp_url) do
    if AuthorizeAgent.resource_ok?(resource, mcp_url),
      do: :ok,
      else: {:error, "invalid_target", "Use this team’s MCP address."}
  end

  defp grant("authorization_code", team, params, now) do
    connection = AgentConnection.get_by_code(team, params["code"])
    connection = connection && Repo.preload(connection, [:user, :agent_client])

    case check_code(connection, params, now) do
      :ok -> if_still_admin(team, connection, now, &issue(&1, :code, now))
      {:error, description} -> {:error, "invalid_grant", description}
    end
  end

  defp grant("refresh_token", team, params, now) do
    token = params["refresh_token"]
    connection = AgentConnection.get_by_refresh_token(team, token)
    connection = connection && Repo.preload(connection, [:user, :agent_client])

    case connection && refresh_match(connection, AgentConnection.hash(token), now) do
      nil ->
        {:error, "invalid_grant", "The refresh token is not valid. Connect again."}

      :expired ->
        {:error, "invalid_grant", "The refresh token is not valid. Connect again."}

      match ->
        with :ok <- check_client(connection, params["client_id"]) do
          if_still_admin(team, connection, now, &issue(&1, match, now))
        end
    end
  end

  defp grant(_other, _team, _params, _now),
    do: {:error, "unsupported_grant_type", "Use authorization_code or refresh_token."}

  @doc """
  Whether a code may be traded: `:ok` or `{:error, description}`. Pure, on a connection
  with its agent client.
  """
  def check_code(nil, _params, _now), do: {:error, "The code is not valid."}

  def check_code(%AgentConnection{} = connection, params, now) do
    cond do
      DateTime.compare(connection.code_expires_at, now) != :gt ->
        {:error, "The code has expired. Connect again."}

      check_client(connection, params["client_id"]) != :ok ->
        {:error, "The code belongs to another agent."}

      params["redirect_uri"] not in [nil, connection.redirect_uri] ->
        {:error, "The redirect URI does not match."}

      not pkce_ok?(params["code_verifier"], connection.code_challenge) ->
        {:error, "The code verifier does not match."}

      true ->
        :ok
    end
  end

  @doc "Whether the PKCE verifier hashes to the challenge (RFC 7636, S256). Pure."
  def pkce_ok?(verifier, challenge) when is_binary(verifier) and is_binary(challenge) do
    computed = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
    Plug.Crypto.secure_compare(computed, challenge)
  end

  def pkce_ok?(_verifier, _challenge), do: false

  @doc """
  Which of a connection's refresh tokens `hash` is: `:current`, `:previous` within its
  #{@grace_seconds} seconds, `:expired` after #{@refresh_days} days without a refresh or
  past the grace, or `nil` for neither. Pure.
  """
  def refresh_match(%AgentConnection{} = connection, hash, now) do
    last = connection.refreshed_at || connection.connected_at

    cond do
      is_nil(last) or DateTime.diff(now, last, :day) >= @refresh_days -> :expired
      connection.refresh_token_hash == hash -> :current
      connection.previous_refresh_token_hash != hash -> nil
      DateTime.compare(connection.previous_refresh_expires_at, now) == :gt -> :previous
      true -> :expired
    end
  end

  # A public client sends its id; when it does, it must be the connection's.
  defp check_client(_connection, nil), do: :ok

  defp check_client(%AgentConnection{agent_client: %AgentClient{client_id: id}}, id), do: :ok
  defp check_client(_connection, _client_id), do: {:error, "invalid_client", "Wrong client."}

  # Someone who lost Owner or Editor in D4H gets no new tokens.
  defp if_still_admin(team, connection, now, fun) do
    if Team.managed_by?(team, connection.user.email, now),
      do: fun.(connection),
      else: {:error, "invalid_grant", "You are no longer a team admin."}
  end

  defp issue(connection, match, now) do
    access = AgentConnection.new_secret(:access)
    refresh = AgentConnection.new_secret(:refresh)

    connection
    |> Ecto.Changeset.change(rotation(connection, match, now))
    |> Ecto.Changeset.change(
      refresh_token_hash: AgentConnection.hash(refresh),
      access_token_hash: AgentConnection.hash(access),
      access_expires_at: DateTime.add(now, @access_seconds, :second),
      refreshed_at: now
    )
    |> Repo.update!()

    {:ok,
     %{
       "access_token" => access,
       "token_type" => "Bearer",
       "expires_in" => @access_seconds,
       "refresh_token" => refresh
     }}
  end

  # A code is used up, and connects. A current refresh token becomes the previous one
  # for the grace; a previous one used in its grace leaves the grace as it was.
  defp rotation(_connection, :code, now),
    do: [code_hash: nil, code_challenge: nil, code_expires_at: nil, connected_at: now]

  defp rotation(connection, :current, now) do
    [
      previous_refresh_token_hash: connection.refresh_token_hash,
      previous_refresh_expires_at: DateTime.add(now, @grace_seconds, :second)
    ]
  end

  defp rotation(_connection, :previous, _now), do: []
end
