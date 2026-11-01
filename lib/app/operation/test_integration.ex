defmodule App.Operation.TestIntegration do
  @moduledoc """
  Adminland › Integrations (#789): one real call to each service SAR Duty depends on,
  made by a SAR Duty site admin. Each test is saved as an `integration_tested` event
  whose data holds the service and its outcome, never the address or number typed. The
  page runs `call/4` with `start_async`, since a few tests wait seconds for an answer.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Adapter.GoogleWallet
  alias App.Adapter.Healthchecks
  alias App.Adapter.Litestream
  alias App.Adapter.Mapbox
  alias App.Adapter.R2
  alias App.Adapter.Twilio
  alias App.Adapter.Website
  alias App.Mailer
  alias App.Mailer.IntegrationTestMailer
  alias App.Model.Event
  alias App.Model.Team
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.CheckTeamKey
  alias App.Worker.IntegrationTestWorker

  # How long a round trip may take before it fails: a backup write reaching R2, and a
  # job on every queue. The refresh and sync queues run one job at a time.
  @backup_wait_ms 15_000
  @jobs_wait_ms 30_000
  @poll_ms 500

  @services ~w(website jobs backups email texts errors d4h maps health apple google)

  def services, do: @services

  @doc """
  Whether this server has what a service's test needs, so the page says Not set up here
  rather than offer a test that can only fail. Production has them all; dev has no
  Litestream or Honeybadger, and often no Wallet keys or Healthchecks.
  """
  def set_up?("backups"), do: R2.configured?()
  def set_up?("texts"), do: Twilio.configured?()
  def set_up?("errors"), do: honeybadger_reports?()
  def set_up?("maps"), do: Mapbox.configured?()
  def set_up?("health"), do: Healthchecks.configured?()
  def set_up?("apple"), do: BuildApplePass.configured?()
  def set_up?("google"), do: BuildGooglePass.configured?()
  def set_up?(service) when service in @services, do: true

  @doc """
  Runs one test. `params` holds what the page sent ("to", "team_id"). Returns
  `{:ok, outcome, message}` or `{:error, outcome, message}`, where `outcome` is the
  word the row shows ("sent", "works", "failed", "behind", "stuck") and `message` the
  toast. An Apple Wallet test that works returns `{:ok, outcome, message, pkpass}`. A
  service that isn't set up here is not called and saves no event.
  """
  def call(service, params, %User{} = user, now \\ DateTime.utc_now())
      when service in @services do
    if set_up?(service),
      do: run_and_record(service, params, user, now),
      else: {:error, "failed", not_set_up(service)}
  end

  defp run_and_record(service, params, user, now) do
    started = System.monotonic_time(:millisecond)
    # The backup test needs Litestream's newest transaction from before its write, which
    # is this event.
    before = if service == "backups", do: Litestream.fetch_metrics()

    event =
      Event.record!(:integration_tested,
        user_id: user.id,
        team_id: team_id(service, params),
        data: %{service: service, outcome: "running"}
      )

    result =
      if service == "backups", do: check_backup(before), else: run(service, params, user, now)

    Event.put_outcome!(event, elem(result, 1), System.monotonic_time(:millisecond) - started)
    result
  end

  defp not_set_up("backups"), do: "Backup not checked. R2 isn't set up on this server."
  defp not_set_up("texts"), do: "Test text not sent. Twilio isn't set up on this server."
  defp not_set_up("errors"), do: "Test error not sent. Honeybadger is off on this server."
  defp not_set_up("maps"), do: "Token not checked. Mapbox has no token on this server."
  defp not_set_up("health"), do: "Nothing pinged. No Healthchecks check is set up on this server."
  defp not_set_up("apple"), do: "Test pass not made. Apple Wallet isn't set up on this server."
  defp not_set_up("google"), do: "Test pass not made. Google Wallet isn't set up on this server."

  defp team_id("d4h", %{"team_id" => id}), do: parse_id(id)
  defp team_id(_service, _params), do: nil

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_id(_id), do: nil

  defp run("website", _params, _user, _now) do
    url = Web.Endpoint.url() <> "/health"

    case Website.fetch_health(url) do
      :ok -> {:ok, "works", "The website answers. #{url} says the app and its database are up."}
      {:error, reason} -> {:error, "failed", "The website didn't answer. #{url}: #{reason}."}
    end
  end

  defp run("jobs", _params, _user, _now) do
    ref = 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64()
    Phoenix.PubSub.subscribe(App.PubSub, IntegrationTestWorker.topic(ref))
    started = System.monotonic_time(:millisecond)
    IntegrationTestWorker.enqueue(ref)
    queues = IntegrationTestWorker.queues()
    waiting = queues |> MapSet.new(&to_string/1) |> wait_for_jobs(started)
    took = seconds(System.monotonic_time(:millisecond) - started)

    if MapSet.size(waiting) == 0 do
      {:ok, "works",
       "Background jobs work. All #{length(queues)} queues ran a test job within #{took}. #{last_sync()}"}
    else
      {:error, "stuck",
       "Background jobs stuck. #{stuck_queues(waiting)} didn't run a test job in #{div(@jobs_wait_ms, 1000)} seconds. #{last_sync()}"}
    end
  end

  defp run("email", params, user, now) do
    to = String.trim(params["to"] || "")

    if to =~ ~r/^[^\s@]+@[^\s@]+$/ do
      send_email(to, user, now)
    else
      {:error, "failed", "Test email not sent. Type an email address."}
    end
  end

  defp run("texts", params, _user, _now) do
    case Service.Phone.normalize(params["to"] || "") do
      nil ->
        {:error, "failed", "Test text not sent. Type a mobile number."}

      e164 ->
        text(e164)
    end
  end

  defp run("errors", _params, user, _now) do
    Honeybadger.notify(%RuntimeError{message: "Integration test from Adminland"},
      metadata: %{user_id: user.id},
      fingerprint: "integration-test"
    )

    {:ok, "sent", "Test error sent. It shows in Honeybadger as Integration test from Adminland."}
  end

  defp run("d4h", params, _user, _now) do
    case params["team_id"] |> parse_id() |> then(&(&1 && Team.get(&1))) do
      nil ->
        {:error, "failed", "Key not checked. Pick a team."}

      %Team{d4h_access_key: key} = team when key in [nil, ""] ->
        {:error, "failed", "Key not checked. #{team.name} has no access key."}

      team ->
        check_key(team)
    end
  end

  defp run("maps", _params, _user, _now) do
    case Mapbox.check_token(Mapbox.build_context()) do
      {:ok, account} ->
        {:ok, "works", "The Mapbox token works. It belongs to the #{account} account."}

      {:error, code} ->
        {:error, "failed", "The Mapbox token doesn't work. Mapbox says #{code}."}
    end
  end

  defp run("health", _params, user, _now) do
    case Healthchecks.log_all("Integration test from Adminland by #{user.email}") do
      {:ok, count} ->
        {:ok, "sent",
         "Test ping sent. #{Service.Format.count(count, one: "%d check", many: "Each of %d checks")} has a line in its log; none went up or down."}

      {:error, reason} ->
        {:error, "failed", "Test ping failed. #{reason}."}
    end
  end

  defp run("apple", _params, user, now) do
    config = :sarduty |> Application.get_env(:apple_pass) |> Map.new()
    pkpass = user |> apple_files(config, now) |> Service.ApplePass.package(config)
    {:ok, "works", "Test pass signed. Open it on an iPhone or a Mac to add it to Wallet.", pkpass}
  rescue
    error -> {:error, "failed", "Test pass not signed. #{Exception.message(error)}"}
  end

  defp run("google", _params, user, now) do
    config = BuildGooglePass.config()
    class = BuildGooglePass.pass_class(config)
    object = google_object(class.id, user, config)

    with {:ok, token} <- GoogleWallet.access_token(config.credentials, now),
         :ok <- GoogleWallet.upsert(token, "genericClass", class),
         :ok <- GoogleWallet.upsert(token, "genericObject", object) do
      url = GoogleWallet.save_url(object.id, config.credentials, now)
      {:ok, "works", "Test pass ready in Google Wallet.", url}
    else
      {:error, reason} ->
        {:error, "failed", "Google Wallet refused the test pass. #{error_text(reason)}"}
    end
  end

  # The backup round trip: the test's event is a write, so it waits for Litestream to
  # see a transaction newer than `before`'s, then for a file in R2 that holds it.
  defp check_backup({:ok, %{txid: txid} = metrics}) when is_integer(txid) do
    started = System.monotonic_time(:millisecond)

    with {:ok, target} <- wait_for_litestream(txid, started),
         {:ok, ms} <- wait_for_r2(target, started) do
      {:ok, "works",
       "Backup works. A test write reached R2 in #{seconds(ms)}. #{sync_errors(metrics.sync_errors)}"}
    else
      {:error, reason} ->
        {:error, "behind",
         "Backup behind. A test write didn't reach R2 in #{div(@backup_wait_ms, 1000)} seconds. #{reason}"}
    end
  end

  defp check_backup(_before),
    do: {:error, "failed", "Backup not checked. Litestream isn't running on this server."}

  # Litestream sees the write within a second: a transaction newer than the one before.
  defp wait_for_litestream(before_txid, started) do
    case Litestream.fetch_metrics() do
      {:ok, %{txid: txid}} when is_integer(txid) and txid > before_txid ->
        {:ok, txid}

      _ ->
        poll(started, "Litestream didn't see it.", fn ->
          wait_for_litestream(before_txid, started)
        end)
    end
  end

  # Then a level 0 file in R2 that holds it.
  defp wait_for_r2(target, started) do
    case R2.fetch_newest_txid() do
      {:ok, newest} when is_integer(newest) and newest >= target ->
        {:ok, System.monotonic_time(:millisecond) - started}

      {:error, reason} ->
        {:error, "R2: #{reason}."}

      _ ->
        poll(started, "Litestream saw it; R2 didn't get it.", fn ->
          wait_for_r2(target, started)
        end)
    end
  end

  defp poll(started, gave_up, again) do
    if System.monotonic_time(:millisecond) - started > @backup_wait_ms do
      {:error, gave_up}
    else
      Process.sleep(@poll_ms)
      again.()
    end
  end

  defp sync_errors(0), do: "No sync errors since Litestream started."
  defp sync_errors(nil), do: ""

  defp sync_errors(n),
    do:
      "#{Service.Format.count(n, one: "%d sync error", many: "%d sync errors")} since Litestream started."

  defp seconds(ms) when ms < 1000, do: "under a second"

  defp seconds(ms),
    do: (ms + 999) |> div(1000) |> Service.Format.count(one: "%d second", many: "%d seconds")

  defp stuck_queues(waiting) do
    names = waiting |> Enum.sort() |> Service.Format.and_list()
    if MapSet.size(waiting) == 1, do: "The #{names} queue", else: "The #{names} queues"
  end

  defp send_email(to, user, now) do
    case to |> IntegrationTestMailer.build(user.email, now) |> Mailer.deliver() do
      {:ok, _} ->
        if dev_mailbox?(),
          do: {:ok, "sent", "Test email in the dev mailbox. Open /dev/mailbox to see it."},
          else: {:ok, "sent", "Test email sent to #{to}."}

      {:error, reason} ->
        {:error, "failed", "Test email not sent. #{error_text(reason)}"}
    end
  end

  defp check_key(team) do
    case CheckTeamKey.call(team) do
      {:ok, %Team{d4h_access_key_owner: nil} = team} ->
        {:ok, "works", "#{team.name}'s key works."}

      {:ok, team} ->
        {:ok, "works", "#{team.name}'s key works. It belongs to #{team.d4h_access_key_owner}."}

      {:error, :refused} ->
        {:error, "failed",
         "#{team.name}'s key was refused. #{D4H.service_name(team)} turned it down."}

      {:error, _} ->
        {:error, "failed",
         "#{D4H.service_name(team)} didn't answer. #{team.name}'s key wasn't checked."}
    end
  end

  defp wait_for_jobs(waiting, started) do
    left = @jobs_wait_ms - (System.monotonic_time(:millisecond) - started)

    if MapSet.size(waiting) == 0 or left <= 0 do
      waiting
    else
      receive do
        {:integration_job_ran, queue} ->
          wait_for_jobs(MapSet.delete(waiting, to_string(queue)), started)
      after
        left -> waiting
      end
    end
  end

  defp last_sync do
    case Event.get_last(:d4h_sync_round) do
      nil ->
        "The sync hasn't run yet."

      event ->
        "The sync last ran #{Service.Format.minutes_ago(event.occurred_at, DateTime.utc_now(), "Etc/UTC")}."
    end
  end

  defp text(e164) do
    body = "SAR Duty test text, sent from Adminland. If you got it, texts work."

    case Twilio.send_sms_with_reason(e164, body) do
      :ok ->
        if Twilio.delivers?(),
          do: {:ok, "sent", "Test text sent to #{Service.Phone.format(e164)}."},
          else: {:ok, "sent", "Test text written to the log. This server doesn't send texts."}

      {:error, %{message: message, code: code}} when is_binary(message) ->
        {:error, "failed",
         "Test text not sent. Twilio says #{String.trim_trailing(message, ".")} (#{code})."}

      {:error, %{status: status}} ->
        {:error, "failed", "Test text not sent. Twilio answered #{status}."}
    end
  end

  defp dev_mailbox?, do: Application.get_env(:sarduty, Mailer)[:adapter] == Swoosh.Adapters.Local

  defp honeybadger_reports? do
    Application.get_env(:honeybadger, :environment_name) not in Application.get_env(
      :honeybadger,
      :exclude_envs,
      [:dev, :test]
    )
  end

  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(reason), do: inspect(reason)

  # A pass of SAR Duty's own: your email, and Test as the team. No web service, so no
  # phone registers it or asks for updates.
  defp apple_files(user, config, now) do
    json = %{
      formatVersion: 1,
      passTypeIdentifier: config.pass_type_id,
      teamIdentifier: config.team_id,
      serialNumber: "integration-test-#{DateTime.to_unix(now)}",
      organizationName: "SAR Duty",
      description: "SAR Duty test pass",
      logoText: "Test",
      backgroundColor: "rgb(28, 45, 66)",
      foregroundColor: "rgb(255, 255, 255)",
      labelColor: "rgb(255, 196, 0)",
      generic: %{primaryFields: [%{key: "name", label: "Test pass", value: user.email}]}
    }

    icon =
      :sarduty |> Application.app_dir("priv/static/images/sarduty-logo-96.png") |> File.read!()

    %{"pass.json" => Jason.encode!(json), "icon.png" => icon}
  end

  defp google_object(class_id, user, config) do
    %{
      id: "#{config.issuer_id}.#{config.host}-integration-test",
      classId: class_id,
      state: "ACTIVE",
      hexBackgroundColor: "#1c2d42",
      cardTitle: %{defaultValue: %{language: "en", value: "Test"}},
      header: %{defaultValue: %{language: "en", value: "Test pass"}},
      subheader: %{defaultValue: %{language: "en", value: user.email}}
    }
  end
end
