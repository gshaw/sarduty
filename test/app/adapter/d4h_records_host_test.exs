defmodule App.Adapter.D4HRecordsHostTest do
  # Not async: it changes the Records host every test reads.
  use ExUnit.Case, async: false

  alias App.Adapter.D4H

  defp custom_fields?(api_host) do
    [access_key: "key", api_host: api_host, d4h_team_id: 1]
    |> D4H.build_context()
    |> D4H.custom_fields?()
  end

  setup do
    host = Application.fetch_env(:sarduty, :records_host)

    on_exit(fn ->
      case host do
        {:ok, host} -> Application.put_env(:sarduty, :records_host, host)
        :error -> Application.delete_env(:sarduty, :records_host)
      end
    end)
  end

  test "a Records team has no custom fields, with or without a port in its host" do
    refute custom_fields?(D4H.records_host())
    assert custom_fields?("api.ca.d4h.org")

    # A local Records in dev, as the dev teams use (docs/records.md).
    Application.put_env(:sarduty, :records_host, "sarduty-records.gshaw.ca:8443")
    refute custom_fields?("sarduty-records.gshaw.ca:8443")
    assert custom_fields?("sarduty-records.gshaw.ca")
  end
end
