defmodule App.Validate.D4HAccessKey do
  import Ecto.Changeset

  alias App.Adapter.D4H

  def call(changeset, access_key_field, api_host_field) do
    changeset
    |> validate_length(access_key_field, min: 5, max: 100)
    |> validate_inclusion(api_host_field, Map.values(D4H.regions()))
    |> validate_d4h_api_auth(access_key_field, api_host_field)
  end

  defp validate_d4h_api_auth(%{valid?: false} = changeset, _, _), do: changeset

  defp validate_d4h_api_auth(changeset, access_key_field, api_host_field) do
    access_key = get_field(changeset, access_key_field)
    api_host = get_field(changeset, api_host_field)
    d4h = D4H.build_context(%{d4h_access_key: access_key, d4h_api_host: api_host})

    try do
      case D4H.fetch_team(d4h) do
        {:error, _} ->
          add_error(changeset, access_key_field, "is unknown or not authorized")

        {:ok, team} ->
          changeset
          |> put_change(:team_title, team.title)
          |> put_change(:team_subdomain, team.subdomain)
      end
    rescue
      e in Mint.TransportError ->
        add_error(changeset, api_host_field, e.message)
    end
  end
end
