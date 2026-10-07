defmodule Web.MapImage do
  @moduledoc """
  Map images served from `/maps/<key>`, where the key is a Mapbox path the app signed.
  The browser never sees the Mapbox token, and the signature means only maps the app drew
  can be fetched, so nobody can spend the token's quota through us.
  """

  alias Plug.Crypto.KeyGenerator
  alias Plug.Crypto.MessageVerifier

  @doc "The local URL for a path from `App.Adapter.Mapbox.static_view_path/4`. Nil for nil."
  def url(nil), do: nil
  def url(path), do: "/maps/" <> MessageVerifier.sign(path, key())

  @doc "The Mapbox path in a key from `url/1`, or `:error` if the app didn't sign it."
  def verify(key), do: MessageVerifier.verify(key, key())

  defp key do
    case :persistent_term.get({__MODULE__, :key}, nil) do
      nil ->
        secret = Application.fetch_env!(:sarduty, Web.Endpoint)[:secret_key_base]
        key = KeyGenerator.generate(secret, "mapbox image")
        :persistent_term.put({__MODULE__, :key}, key)
        key

      key ->
        key
    end
  end
end
