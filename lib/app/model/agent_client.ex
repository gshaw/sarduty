defmodule App.Model.AgentClient do
  use App, :model

  alias App.Model.AgentClient
  alias App.Repo

  # An AI agent that registered itself (#761, RFC 7591): its public client id, the name
  # it gave, and where it asks to be sent back. It has no secret: agents are public
  # clients and PKCE stands in. Registering proves nothing, so the name shows only for an
  # agent on the admin's own computer; a web agent's name comes from @web_agents.

  # Web agents SAR Duty knows, by their whole return address. Adding one is a line.
  @web_agents %{
    "https://claude.ai/api/mcp/auth_callback" => "Claude",
    "https://claude.com/api/mcp/auth_callback" => "Claude",
    "https://chatgpt.com/connector_platform_oauth_redirect" => "ChatGPT"
  }

  # App links that open an editor on the admin's own computer.
  @app_schemes ["vscode", "cursor"]
  @loopback_hosts ["localhost", "127.0.0.1", "[::1]", "::1"]
  @max_name 40
  @max_redirect_uris 10
  @prune_after_days 1

  schema "agent_clients" do
    field :client_id, :string
    field :name, :string
    field :redirect_uris, {:array, :string}
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Where a return address sends the code: `{:web, name}` for a web agent on the list,
  `:local` for the admin's own computer, `{:unknown, host}` for any other `https`
  address, and `:invalid` for anything else (`javascript:`, `data:`, plain `http` to
  another host, a fragment).
  """
  def redirect_kind(uri) when is_binary(uri) do
    case Map.fetch(@web_agents, uri) do
      {:ok, name} -> {:web, name}
      :error -> uri |> URI.parse() |> parsed_kind()
    end
  end

  def redirect_kind(_uri), do: :invalid

  defp parsed_kind(%URI{fragment: fragment}) when is_binary(fragment), do: :invalid
  defp parsed_kind(%URI{scheme: "http", host: host}) when host in @loopback_hosts, do: :local
  defp parsed_kind(%URI{scheme: scheme}) when scheme in @app_schemes, do: :local

  defp parsed_kind(%URI{scheme: "https", host: host}) when is_binary(host) and host != "",
    do: {:unknown, host}

  defp parsed_kind(_uri), do: :invalid

  @doc """
  The name the Allow page and Connected agents show for an agent sent back to `uri`:
  the list's name for a web agent, otherwise the one it gave, escaped by the page, cut
  at #{@max_name} characters, and "An AI agent" when it gave none.
  """
  def display_name(%AgentClient{name: name}, uri) do
    case redirect_kind(uri) do
      {:web, listed} -> listed
      _local -> given_name(name)
    end
  end

  defp given_name(name) when is_binary(name) do
    case name |> String.trim() |> String.slice(0, @max_name) |> String.trim() do
      "" -> "An AI agent"
      trimmed -> trimmed
    end
  end

  defp given_name(_name), do: "An AI agent"

  @doc """
  A registration from an agent's JSON (RFC 7591): `{:ok, changeset}`, or `{:error,
  description}` for the agent to read. Every return address must at least be one we can
  name on the refused page; whether it may connect is decided at Allow.
  """
  def build(params, client_id) when is_map(params) do
    uris = params["redirect_uris"]
    name = if is_binary(params["client_name"]), do: String.slice(params["client_name"], 0, 200)

    cond do
      not (is_list(uris) and uris != [] and length(uris) <= @max_redirect_uris) ->
        {:error, "Send redirect_uris: a list of 1 to #{@max_redirect_uris} addresses."}

      Enum.any?(uris, &(redirect_kind(&1) == :invalid)) ->
        {:error, "Every redirect URI must be https, or http on localhost, or an app link."}

      true ->
        client = %AgentClient{client_id: client_id, name: name, redirect_uris: uris}
        {:ok, client |> change() |> unique_constraint(:client_id)}
    end
  end

  def get_by_client_id(client_id) when is_binary(client_id),
    do: Repo.get_by(AgentClient, client_id: client_id)

  def get_by_client_id(_client_id), do: nil

  @doc """
  Deletes registrations over a day old that no agent connected with. Returns how many.
  """
  def prune(now) do
    cutoff = DateTime.add(now, -@prune_after_days, :day)

    connected =
      from(a in "agent_connections",
        where: a.agent_client_id == parent_as(:client).id and not is_nil(a.connected_at),
        select: 1
      )

    unused =
      from(c in AgentClient,
        as: :client,
        where: c.inserted_at < ^cutoff and not exists(connected)
      )

    {count, _} = Repo.delete_all(unused)
    count
  end
end
