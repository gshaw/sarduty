defmodule App.Adapter.Healthchecks do
  @moduledoc """
  Pings Healthchecks.io, which emails when a run is late or failed. Optional: without a
  check's URL, nothing is sent. Each run pings `/start` when it is queued and success or
  `/fail` once its last job finishes, so Healthchecks also alerts on a run that takes too
  long. See docs/d4h-sync.md.
  """

  require Logger

  # Config keys for each check's ping URL, from config/runtime.exs.
  @checks %{refresh: :healthchecks_url, sync: :healthchecks_sync_url}

  @doc "Pings a check: `:start`, `:success`, or `:fail`. A failed ping is only logged."
  def ping(check, signal) when signal in [:start, :success, :fail] do
    case Application.get_env(:sarduty, Map.fetch!(@checks, check)) do
      url when url in [nil, ""] -> :ok
      url -> send_ping(url <> suffix(signal))
    end
  end

  @doc """
  Adds a line to each set-up check's log without changing whether it is up or down
  (Adminland's test, #789). `{:ok, count}` of checks pinged, or `{:error, reason}`.
  """
  def log_all(message) do
    urls =
      for {_check, key} <- @checks,
          url = Application.get_env(:sarduty, key),
          url not in [nil, ""],
          do: url

    results =
      Enum.map(urls, fn url ->
        Req.post(
          url <> "/log",
          [body: message, retry: false] ++ Application.get_env(:sarduty, __MODULE__, [])
        )
      end)

    case Enum.find(results, &(not match?({:ok, %{status: 200}}, &1))) do
      nil -> {:ok, length(urls)}
      {:ok, %{status: status}} -> {:error, "Healthchecks answered #{status}"}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp suffix(:start), do: "/start"
  defp suffix(:success), do: ""
  defp suffix(:fail), do: "/fail"

  defp send_ping(url) do
    case Req.get(url, Application.get_env(:sarduty, __MODULE__, [])) do
      {:ok, %{status: 200}} -> :ok
      other -> Logger.warning("Healthchecks ping failed: #{inspect(other)}")
    end
  end
end
