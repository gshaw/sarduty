defmodule App.Adapter.Website do
  @moduledoc """
  SAR Duty's own `/health` (Web.Health), fetched from outside like Fly's check: through
  DNS, the certificate, and Fly's proxy, to the app and its database.
  """

  @doc "`:ok` for a 200, or `{:error, reason}`."
  def fetch_health(url) do
    case Req.get(url, [retry: false, receive_timeout: 10_000] ++ test_options()) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, "#{status} #{body}" |> String.trim()}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp test_options, do: :sarduty |> Application.get_env(__MODULE__, []) |> Keyword.take([:plug])
end
