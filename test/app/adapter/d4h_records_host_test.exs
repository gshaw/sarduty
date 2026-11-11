defmodule App.Adapter.D4HRecordsHostTest do
  # Not async: it changes the Records host every test reads.
  use ExUnit.Case, async: false

  alias App.Adapter.D4H

  setup do
    host = Application.fetch_env(:sarduty, :records_host)

    on_exit(fn ->
      case host do
        {:ok, host} -> Application.put_env(:sarduty, :records_host, host)
        :error -> Application.delete_env(:sarduty, :records_host)
      end
    end)
  end

  test "a Records host is Records with or without a port, and only with its own" do
    assert D4H.records?(D4H.records_host())
    refute D4H.records?("api.ca.d4h.org")

    # A local Records in dev, as the dev teams use (docs/records.md).
    Application.put_env(:sarduty, :records_host, "sarduty-records.gshaw.ca:8443")
    assert D4H.records?("sarduty-records.gshaw.ca:8443")
    refute D4H.records?("sarduty-records.gshaw.ca")
  end
end
