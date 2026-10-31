defmodule App.Operation.RegisterAgentClient do
  @moduledoc """
  An AI agent registers itself (#761, RFC 7591), so nobody hands out client ids. Any
  `https` return address is kept, so an agent SAR Duty doesn't know reaches the refused
  page at Allow, which names it; only an address that page can't name is refused here.
  App.Model.AgentClient prunes registrations nobody connected with.
  """

  alias App.Model.AgentClient
  alias App.Model.AgentConnection
  alias App.Repo

  @doc "`{:ok, client}`, or `{:error, description}` for the agent to read."
  def call(params) when is_map(params) do
    client_id = "sarduty_client_" <> AgentConnection.new_secret(:code)

    with {:ok, changeset} <- AgentClient.build(params, client_id) do
      {:ok, Repo.insert!(changeset)}
    end
  end

  def call(_params), do: {:error, "Send a JSON object."}

  @doc "The registration response (RFC 7591 section 3.2.1)."
  def response(%AgentClient{} = client) do
    %{
      "client_id" => client.client_id,
      "client_id_issued_at" => DateTime.to_unix(client.inserted_at),
      "client_name" => client.name,
      "redirect_uris" => client.redirect_uris,
      "grant_types" => ["authorization_code", "refresh_token"],
      "response_types" => ["code"],
      "token_endpoint_auth_method" => "none"
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
