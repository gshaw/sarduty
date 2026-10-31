defmodule Web.OAuthController do
  @moduledoc """
  How an AI agent connects to a team's MCP endpoint (#761): the MCP authorization spec
  (2025-11-25), written by hand. Each team is its own authorization server, issuer
  `/teams/:subdomain`, so the URL always names the team.

  - Protected resource metadata (RFC 9728) and authorization server metadata (RFC
    8414), under `/.well-known/`.
  - `POST /teams/:subdomain/oauth/register`: dynamic client registration (RFC 7591).
  - `POST /teams/:subdomain/oauth/token`: codes and refresh tokens for tokens.
  - `POST /teams/:subdomain/oauth/authorize`: Allow or Cancel from the Allow page,
    Web.AgentAuthorizeLive, which is the GET.

  The JSON ones take no session or CSRF token and answer browser preflights, since MCP
  Inspector runs these steps from a web page. A team with Agents off is not found.
  See docs/mcp.md.
  """
  use Web, :controller

  alias App.Model.AgentClient
  alias App.Model.Team
  alias App.Operation.AuthorizeAgent
  alias App.Operation.ExchangeAgentToken
  alias App.Operation.RegisterAgentClient
  alias App.RateLimit
  alias Web.VerifyLimit

  @register_limit 20
  @register_scale :timer.hours(1)
  @token_limit 120
  @token_scale :timer.minutes(15)

  plug :cors when action in [:resource_metadata, :server_metadata, :register, :token, :preflight]

  @doc "The team's MCP address: what an agent connects to, and the OAuth resource."
  def mcp_url(subdomain), do: url(~p"/teams/#{subdomain}/mcp")

  @doc "Where the 401 sends an agent: the protected resource metadata (RFC 9728)."
  def resource_metadata_url(subdomain),
    do: url(~p"/.well-known/oauth-protected-resource/teams/#{subdomain}/mcp")

  @doc "The team's authorization server, its issuer."
  def issuer(subdomain), do: url(~p"/teams/#{subdomain}")

  def resource_metadata(conn, %{"subdomain" => subdomain}) do
    with_team(conn, subdomain, fn team ->
      json(conn, %{
        "resource" => mcp_url(team.subdomain),
        "authorization_servers" => [issuer(team.subdomain)],
        "bearer_methods_supported" => ["header"],
        "resource_name" => "SAR Duty: #{team.name}"
      })
    end)
  end

  def server_metadata(conn, %{"subdomain" => subdomain}) do
    with_team(conn, subdomain, fn team ->
      json(conn, %{
        "issuer" => issuer(team.subdomain),
        "authorization_endpoint" => url(~p"/teams/#{team}/oauth/authorize"),
        "token_endpoint" => url(~p"/teams/#{team}/oauth/token"),
        "registration_endpoint" => url(~p"/teams/#{team}/oauth/register"),
        "response_types_supported" => ["code"],
        "grant_types_supported" => ["authorization_code", "refresh_token"],
        "code_challenge_methods_supported" => ["S256"],
        "token_endpoint_auth_methods_supported" => ["none"]
      })
    end)
  end

  def register(conn, %{"subdomain" => subdomain}) do
    with_team(conn, subdomain, fn _team ->
      with :ok <- limit(conn, "agent_register", @register_limit, @register_scale),
           {:ok, client} <- conn |> json_body() |> RegisterAgentClient.call() do
        conn |> put_status(201) |> no_store() |> json(RegisterAgentClient.response(client))
      else
        :limited ->
          oauth_error(conn, 429, "slow_down", "Too many registrations. Try again later.")

        {:error, description} ->
          oauth_error(conn, 400, "invalid_client_metadata", description)
      end
    end)
  end

  def token(conn, %{"subdomain" => subdomain} = params) do
    with_team(conn, subdomain, fn team ->
      with :ok <- limit(conn, "agent_token", @token_limit, @token_scale),
           {:ok, response} <- ExchangeAgentToken.call(team, mcp_url(team.subdomain), params) do
        conn |> no_store() |> json(response)
      else
        :limited -> oauth_error(conn, 429, "slow_down", "Too many requests. Try again later.")
        {:error, error, description} -> oauth_error(conn, 400, error, description)
      end
    end)
  end

  @doc "A browser's preflight before one of the JSON requests above."
  def preflight(conn, _params) do
    conn
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header(
      "access-control-allow-headers",
      "content-type, authorization, mcp-protocol-version"
    )
    |> put_resp_header("access-control-max-age", "86400")
    |> send_resp(204, "")
  end

  @doc """
  Allow or Cancel on the Allow page. The request is read again, as the page read it, so
  nothing the form sends is trusted beyond what the agent registered.
  """
  def authorize(conn, %{"subdomain" => subdomain} = params) do
    team = enabled_team(subdomain) || raise Web.Status.NotFound
    client = AgentClient.get_by_client_id(params["client_id"])

    case AuthorizeAgent.check(params, client, mcp_url(team.subdomain)) do
      {:ok, request} -> decide(conn, team, request, params["decision"])
      {:redirect, url} -> redirect(conn, external: url)
      _bad_link_or_unknown -> raise Web.Status.NotFound
    end
  end

  defp decide(conn, team, request, "allow") do
    case AuthorizeAgent.allow(team, conn.assigns.current_user, request) do
      {:ok, url} -> redirect(conn, external: url)
      {:error, :not_allowed} -> redirect(conn, external: AuthorizeAgent.deny_url(request))
    end
  end

  defp decide(conn, _team, request, _cancel),
    do: redirect(conn, external: AuthorizeAgent.deny_url(request))

  defp with_team(conn, subdomain, fun) do
    case enabled_team(subdomain) do
      nil -> conn |> put_status(404) |> json(%{"error" => "Not found"})
      team -> fun.(team)
    end
  end

  @doc "The team when it has Agents on, or nil."
  def enabled_team(subdomain) when is_binary(subdomain) do
    case Team.get_by(subdomain: subdomain) do
      %Team{mcp_enabled: true} = team -> team
      _off_or_missing -> nil
    end
  end

  # Plug.Parsers puts a JSON body's object straight into params, next to the path's.
  defp json_body(conn), do: Map.drop(conn.body_params, ["_json"])

  defp limit(conn, prefix, limit, scale) do
    key = "#{prefix}:#{conn |> VerifyLimit.client_ip() |> RateLimit.ip_key()}"
    if RateLimit.inc(key, scale) <= limit, do: :ok, else: :limited
  end

  defp cors(conn, _opts), do: put_resp_header(conn, "access-control-allow-origin", "*")

  defp no_store(conn), do: put_resp_header(conn, "cache-control", "no-store")

  defp oauth_error(conn, status, error, description) do
    conn
    |> put_status(status)
    |> no_store()
    |> json(%{"error" => error, "error_description" => description})
  end
end
