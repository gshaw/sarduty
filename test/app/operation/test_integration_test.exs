defmodule App.Operation.TestIntegrationTest do
  use App.DataCase

  import App.AccountsFixtures
  import Swoosh.TestAssertions

  alias App.Adapter.Litestream
  alias App.Adapter.R2
  alias App.Model.Event
  alias App.Operation.TestIntegration

  setup do
    %{user: user_fixture(%{email: "alex.chen@example.com"})}
  end

  defp last_event(service), do: Event.get_last_by(:integration_tested, "service")[service]

  test "each test is saved as an event with its outcome, never what was typed", %{user: user} do
    assert {:ok, "sent", _} = TestIntegration.call("email", %{"to" => "sam@example.com"}, user)

    event = last_event("email")
    assert event.data == %{"service" => "email", "outcome" => "sent"}
    assert event.user_id == user.id
    assert is_integer(event.duration_ms)
  end

  test "email: sends the test email to the address typed", %{user: user} do
    assert {:ok, "sent", "Test email sent to sam@example.com."} =
             TestIntegration.call("email", %{"to" => " sam@example.com "}, user)

    assert_email_sent(fn email ->
      assert email.to == [{"", "sam@example.com"}]
      assert email.subject == "Test email from SAR Duty"
      assert email.text_body =~ "sent by alex.chen@example.com"
    end)

    assert {:error, "failed", "Test email not sent. Type an email address."} =
             TestIntegration.call("email", %{"to" => "sam"}, user)
  end

  @tag :capture_log
  test "texts: Twilio's own reason when it refuses", %{user: user} do
    text_login_fixture()

    Req.Test.stub(App.Adapter.Twilio, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "code" => 21_211,
        "message" => "The 'To' number is not a valid phone number."
      })
    end)

    assert {:error, "failed",
            "Test text not sent. Twilio says The 'To' number is not a valid phone number (21211)."} =
             TestIntegration.call("texts", %{"to" => "604-555-0112"}, user)

    assert {:error, "failed", "Test text not sent. Type a mobile number."} =
             TestIntegration.call("texts", %{"to" => "12"}, user)
  end

  test "texts: sends to the number typed", %{user: user} do
    text_login_fixture()

    Req.Test.stub(App.Adapter.Twilio, fn conn ->
      conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"sid" => "SM1"})
    end)

    assert {:ok, "sent", "Test text sent to 604-555-0112."} =
             TestIntegration.call("texts", %{"to" => "604-555-0112"}, user)
  end

  test "a service this server doesn't have isn't called, and saves no event", %{user: user} do
    refute TestIntegration.set_up?("errors")
    assert TestIntegration.set_up?("email")

    assert {:error, "failed", "Test error not sent. Honeybadger is off on this server."} =
             TestIntegration.call("errors", %{}, user)

    assert last_event("errors") == nil
  end

  test "website: fetches /health", %{user: user} do
    Req.Test.stub(App.Adapter.Website, fn conn ->
      assert conn.request_path == "/health"
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    assert {:ok, "works", _} = TestIntegration.call("website", %{}, user)

    Req.Test.stub(App.Adapter.Website, &Plug.Conn.send_resp(&1, 503, "database down"))

    assert {:error, "failed", message} = TestIntegration.call("website", %{}, user)
    assert message =~ "503 database down"
  end

  test "jobs: an empty job runs on every queue", %{user: user} do
    assert {:ok, "works", message} = TestIntegration.call("jobs", %{}, user)
    assert message =~ "All 4 queues ran a test job"
    assert message =~ "The sync hasn't run yet."
  end

  test "maps: asks Mapbox whether the token is valid, and nothing else", %{user: user} do
    Req.Test.stub(App.Adapter.Mapbox, fn conn ->
      assert conn.request_path == "/tokens/v2"
      Req.Test.json(conn, %{"code" => "TokenValid", "token" => %{"user" => "sarduty"}})
    end)

    assert {:ok, "works", "The Mapbox token works. It belongs to the sarduty account."} =
             TestIntegration.call("maps", %{}, user)

    Req.Test.stub(App.Adapter.Mapbox, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"code" => "TokenRevoked"})
    end)

    assert {:error, "failed", "The Mapbox token doesn't work. Mapbox says TokenRevoked."} =
             TestIntegration.call("maps", %{}, user)
  end

  test "health: a log ping on each set-up check", %{user: user} do
    assert {:error, "failed", _} = TestIntegration.call("health", %{}, user)

    Application.put_env(:sarduty, :healthchecks_url, "https://hc.test/refresh")
    on_exit(fn -> Application.delete_env(:sarduty, :healthchecks_url) end)

    Req.Test.stub(App.Adapter.Healthchecks, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/refresh/log"
      Plug.Conn.send_resp(conn, 200, "OK")
    end)

    assert {:ok, "sent", message} = TestIntegration.call("health", %{}, user)
    assert message =~ "1 check has a line in its log"
  end

  test "d4h: needs a team with a key", %{user: user} do
    assert {:error, "failed", "Key not checked. Pick a team."} =
             TestIntegration.call("d4h", %{"team_id" => ""}, user)
  end

  test "wallets: say when they aren't set up", %{user: user} do
    assert {:error, "failed", _} = TestIntegration.call("apple", %{}, user)
    assert {:error, "failed", _} = TestIntegration.call("google", %{}, user)
  end

  describe "backups" do
    setup do
      original = Application.get_env(:sarduty, R2)

      Application.put_env(
        :sarduty,
        R2,
        Keyword.merge(original,
          account_id: "acct",
          access_key_id: "id",
          secret_access_key: "secret"
        )
      )

      on_exit(fn -> Application.put_env(:sarduty, R2, original) end)
    end

    test "waits for the test's own write to reach R2", %{user: user} do
      # Litestream sees one more transaction once the event is saved.
      Req.Test.stub(Litestream, fn conn ->
        calls = Process.get(:metrics_calls, 0)
        Process.put(:metrics_calls, calls + 1)
        txid = if calls == 0, do: 0x1CE73, else: 0x1CE74

        Plug.Conn.send_resp(
          conn,
          200,
          "litestream_txid{db=\"/db\"} #{txid}\nlitestream_sync_error_count{db=\"/db\"} 0\n"
        )
      end)

      Req.Test.stub(R2, fn conn ->
        assert conn.request_path == "/sarduty-db"
        assert conn.query_params["prefix"] == "database/0000/"

        Plug.Conn.send_resp(conn, 200, """
        <ListBucketResult><Contents><Key>database/0000/000000000001ce73-000000000001ce73.ltx</Key></Contents>
        <Contents><Key>database/0000/000000000001ce74-000000000001ce74.ltx</Key></Contents></ListBucketResult>
        """)
      end)

      assert {:ok, "works", message} = TestIntegration.call("backups", %{}, user)
      assert message =~ "Backup works. A test write reached R2 in"
      assert message =~ "No sync errors since Litestream started."
      assert last_event("backups").data["outcome"] == "works"
    end

    test "says when Litestream isn't running", %{user: user} do
      Req.Test.stub(Litestream, &Plug.Conn.send_resp(&1, 500, ""))

      assert {:error, "failed", "Backup not checked. Litestream isn't running on this server."} =
               TestIntegration.call("backups", %{}, user)
    end
  end

  test "Litestream's metrics and R2's newest file are read from their text" do
    text =
      "# HELP x\nlitestream_txid{db=\"/a\"} 118387\nlitestream_sync_error_count{db=\"/a\"} 2\n"

    assert Litestream.metric(text, "litestream_txid") == 118_387
    assert Litestream.metric(text, "litestream_sync_error_count") == 2
    assert Litestream.metric(text, "litestream_missing") == nil

    xml =
      "<Key>database/0000/0000000000000001-000000000001ce73.ltx</Key><Key>database/0000/000000000001ce74-000000000001ce75.ltx</Key>"

    assert R2.newest_txid(xml) == 0x1CE75
    assert R2.newest_txid("<ListBucketResult/>") == nil
  end
end
