defmodule App.Operation.RefreshD4HDataTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Operation.RefreshD4HData

  test "a team without a key isn't refreshed" do
    assert RefreshD4HData.call(team_fixture()) == {:error, :no_key}
  end

  test "a key D4H rejects comes back as an error for a person to fix" do
    team = team_fixture(%{d4h_access_key: "expired-key"})
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 401, ""))

    assert RefreshD4HData.call(team) == {:error, {:key_rejected, 401}}

    assert RefreshD4HData.error_message({:key_rejected, 401}) ==
             "D4H rejected the team key (401). Save a new one in Team Settings."
  end
end
