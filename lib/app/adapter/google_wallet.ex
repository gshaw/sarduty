defmodule App.Adapter.GoogleWallet do
  @moduledoc """
  The Google Wallet API, as the `sarduty-wallet` service account. Google keeps the pass,
  so a change is sent here and every saved copy updates; there is no phone to push to.
  """

  require Logger

  @api "https://walletobjects.googleapis.com/walletobjects/v1"
  @token_url "https://oauth2.googleapis.com/token"
  @scope "https://www.googleapis.com/auth/wallet_object.issuer"

  @doc """
  The service account's credentials, from the key file's JSON: `"client_email"` and
  `"private_key"`.
  """
  def credentials(json) when is_binary(json), do: Jason.decode!(json)

  @doc "An access token for the Wallet API, good for an hour."
  def access_token(credentials, now) do
    assertion =
      sign(
        %{
          iss: credentials["client_email"],
          scope: @scope,
          aud: @token_url,
          iat: DateTime.to_unix(now),
          exp: DateTime.to_unix(now) + 3600
        },
        credentials
      )

    response =
      request!(
        url: @token_url,
        method: :post,
        form: [grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: assertion]
      )

    case response do
      %{status: 200, body: %{"access_token" => token}} -> {:ok, token}
      %{status: status, body: body} -> log_error("token", status, body)
    end
  end

  @doc """
  Creates or replaces a `"genericClass"` or `"genericObject"`. Replacing sends the whole
  thing, so a field left out is cleared.
  """
  def upsert(token, resource, %{id: id} = body) do
    case request!(token, :put, "/#{resource}/#{id}", body) do
      %{status: 200} -> :ok
      %{status: 404} -> insert(token, resource, body)
      %{status: status, body: body} -> log_error(resource, status, body)
    end
  end

  defp insert(token, resource, body) do
    case request!(token, :post, "/#{resource}", body) do
      %{status: 200} -> :ok
      %{status: status, body: body} -> log_error(resource, status, body)
    end
  end

  @doc """
  The "Add to Google Wallet" link for an object that already exists. The link names the
  object and nothing else, so it can't change what's on the pass.
  """
  def save_url(object_id, credentials, now) do
    jwt =
      sign(
        %{
          iss: credentials["client_email"],
          aud: "google",
          typ: "savetowallet",
          iat: DateTime.to_unix(now),
          payload: %{genericObjects: [%{id: object_id}]}
        },
        credentials
      )

    "https://pay.google.com/gp/v/save/#{jwt}"
  end

  @doc "A JWT signed RS256 with the service account's key."
  def sign(claims, %{"private_key" => pem}) do
    input = encode(%{alg: "RS256", typ: "JWT"}) <> "." <> encode(claims)
    [entry] = :public_key.pem_decode(pem)
    signature = :public_key.sign(input, :sha256, :public_key.pem_entry_decode(entry))
    input <> "." <> Base.url_encode64(signature, padding: false)
  end

  defp encode(map), do: map |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp request!(token, method, path, body) do
    request!(url: @api <> path, method: method, json: body, auth: {:bearer, token})
  end

  defp request!(options) do
    options
    |> Keyword.put(:retry, false)
    |> Keyword.merge(Application.get_env(:sarduty, App.Adapter.GoogleWallet, []))
    |> Req.request!()
  end

  defp log_error(what, status, body) do
    Logger.warning("Google Wallet #{what} failed: #{status} #{inspect(body)}")
    {:error, status}
  end
end
