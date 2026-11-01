defmodule Web.Admin.IntegrationsLive do
  use Web, :live_view_app_layout

  alias App.Adapter.Twilio
  alias App.Model.Event
  alias App.Model.Team
  alias App.Operation.TestIntegration
  alias App.Worker.IntegrationTestWorker

  # Adminland › Integrations (#789): a row per service SAR Duty depends on, its last test
  # as a marker, and a button that makes one real call. A test runs in start_async, since
  # some wait seconds for an answer; a toast says how it went and the row keeps the
  # outcome. The three that need an answer, where an email or a text goes and which
  # team's key, ask it in a dialog first. A service this server doesn't have says Not set
  # up here and offers no test. The Wallet tests are links to
  # Web.Admin.IntegrationPassController.
  @asks ["email", "texts", "d4h"]
  @runs ["website", "jobs", "backups", "email", "texts", "errors", "d4h", "maps", "health"]

  # Times on this page are SAR Duty's own, in BC.
  @timezone "America/Vancouver"

  def mount(_params, _session, socket) do
    teams =
      Team.get_all()
      |> Enum.filter(&(&1.d4h_access_key not in [nil, ""]))
      |> Enum.sort_by(&String.downcase(&1.name))

    set_up = Map.new(TestIntegration.services(), &{&1, TestIntegration.set_up?(&1)})

    {:ok,
     socket
     |> assign(page_title: "Integrations", teams: teams, set_up: set_up)
     |> assign(running: MapSet.new(), asking: nil)
     |> assign(email_to: socket.assigns.current_user.email, text_to: "", team_id: nil)
     |> assign_last_tests()}
  end

  defp assign_last_tests(socket),
    do:
      assign(socket,
        last: Event.get_last_by(:integration_tested, "service"),
        now: DateTime.utc_now()
      )

  @doc "SAR Duty's own parts, then the services it calls: `{key, name, detail, used for}`."
  def groups,
    do: [
      {"SAR Duty",
       [
         {"website", "Website", "#{Web.Endpoint.host()}/health",
          "Fly's check every 15 seconds: the app answers and its database replies"},
         {"jobs", "Background jobs", "Oban, #{length(IntegrationTestWorker.queues())} queues",
          "Reminders, emails, passes, and the D4H sync and refresh"},
         {"backups", "Backups", "Litestream to R2",
          "A copy of the database, kept up to the second"}
       ]},
      {"Services",
       [
         {"email", "Email", "Cloudflare",
          "Login codes, reminders, replies, letters, and team emails"},
         {"texts", "Texts", "Twilio", "Login codes by text"},
         {"errors", "Errors", "Honeybadger", "Errors on pages and in jobs"},
         {"d4h", "D4H", "Each team's key", "Everything a team reads and sends, Records too"},
         {"maps", "Maps", "Mapbox", "Maps on activities and places, and place search"},
         {"health", "Health checks", "Healthchecks.io",
          "Alerts when the nightly refresh or the D4H sync is late"},
         {"apple", "Apple Wallet", apple_detail(), "ID cards on iPhones"},
         {"google", "Google Wallet", "Google", "ID cards on Android phones"}
       ]}
    ]

  def render(assigns) do
    ~H"""
    <h1 class="title">Integrations</h1>
    <p class="mb-6 max-w-3xl">
      Each test makes one real call to the service. Every test is saved in <.a
        id="integrations-events"
        navigate={~p"/admin/events?kind=integration_tested"}
      >Events</.a>.
    </p>
    <div id="integrations" class="integration-board">
      <section
        :for={{group, services} <- groups()}
        id={"integrations-#{group_id(group)}"}
        aria-labelledby={"integrations-#{group_id(group)}-title"}
      >
        <h2 id={"integrations-#{group_id(group)}-title"} class="integration-group">{group}</h2>
        <ul class="integration-rows">
          <li
            :for={{key, name, detail, used_for} <- services}
            id={"integration-#{key}"}
            class="integration-row"
          >
            <div class="integration-name" title={used_for}>
              <span class="font-semibold">{name}</span><span class="text-text-muted">{detail}</span>
            </div>
            <.last_test
              id={"integration-#{key}-last"}
              set_up={@set_up[key]}
              event={@last[key]}
              now={@now}
            />
            <div class="integration-test">
              <.test_button :if={@set_up[key]} key={key} running={key in @running} />
            </div>
          </li>
        </ul>
      </section>
    </div>
    <.test_dialog
      :if={@asking}
      service={@asking}
      email_to={@email_to}
      text_to={@text_to}
      team_id={@team_id}
      teams={@teams}
    />
    """
  end

  defp group_id(group), do: group |> String.downcase() |> String.replace(" ", "-")

  attr :id, :string, required: true
  attr :set_up, :boolean, required: true
  attr :event, :any, required: true
  attr :now, DateTime, required: true

  defp last_test(%{set_up: false} = assigns) do
    ~H"""
    <span id={@id} class="integration-status">
      <span class="marker text-text-muted">Not set up here</span>
    </span>
    """
  end

  defp last_test(%{event: nil} = assigns) do
    ~H"""
    <span id={@id} class="integration-status">
      <span class="marker marker-untested text-text-muted">Never tested</span>
    </span>
    """
  end

  defp last_test(assigns) do
    assigns = assign(assigns, outcome: assigns.event.data["outcome"])

    ~H"""
    <span
      id={@id}
      class="integration-status"
      title={Service.Format.month_day_time(@event.occurred_at, timezone())}
    >
      <span class={["marker", marker_class(@outcome), failed?(@outcome) && "text-danger-text"]}>
        {outcome_label(@outcome)}
      </span>
      <span class="text-text-muted">
        · {Service.Format.time_ago(@event.occurred_at, @now, timezone())}
      </span>
    </span>
    """
  end

  defp timezone, do: @timezone

  defp marker_class(outcome) when outcome in ["sent", "works"], do: "marker-works"
  defp marker_class("running"), do: nil
  defp marker_class(_outcome), do: "marker-failed"

  defp failed?(outcome), do: outcome not in ["sent", "works", "running"]

  # A test the server stopped before it answered, as in a deploy, is still "running".
  defp outcome_label("running"), do: "Didn't finish"
  defp outcome_label(outcome), do: String.capitalize(outcome)

  attr :key, :string, required: true
  attr :running, :boolean, required: true

  # While a test runs its button stays in place, busy, so the column doesn't move.
  defp test_button(%{running: true} = assigns) do
    ~H"""
    <.button id={"test-#{@key}-busy"} type="button" size={:sm} disabled>
      <span class="spinner" aria-hidden="true"></span>{busy_label(@key)}
    </.button>
    """
  end

  defp test_button(%{key: key} = assigns) when key in @asks do
    ~H"""
    <.button id={"test-#{@key}"} type="button" size={:sm} phx-click="ask" phx-value-service={@key}>
      {button_label(@key)}
    </.button>
    """
  end

  defp test_button(%{key: "apple"} = assigns) do
    ~H"""
    <.button id="test-apple" size={:sm} href={~p"/admin/integrations/apple-pass"}>
      Download test pass
    </.button>
    """
  end

  defp test_button(%{key: "google"} = assigns) do
    ~H"""
    <.button id="test-google" size={:sm} href={~p"/admin/integrations/google-pass"}>
      Add test pass
    </.button>
    """
  end

  defp test_button(assigns) do
    ~H"""
    <.button id={"test-#{@key}"} type="button" size={:sm} phx-click="test" phx-value-service={@key}>
      {button_label(@key)}
    </.button>
    """
  end

  defp button_label("website"), do: "Check website"
  defp button_label("jobs"), do: "Run test jobs"
  defp button_label("backups"), do: "Check backup"
  defp button_label("email"), do: "Send test email…"
  defp button_label("texts"), do: "Send test text…"
  defp button_label("errors"), do: "Send test error"
  defp button_label("d4h"), do: "Check key…"
  defp button_label("maps"), do: "Check token"
  defp button_label("health"), do: "Send test ping"

  defp busy_label(key) when key in ["email", "texts", "errors", "health"], do: "Sending…"
  defp busy_label("jobs"), do: "Running…"
  defp busy_label(_key), do: "Checking…"

  attr :service, :string, required: true
  attr :email_to, :string
  attr :text_to, :string
  attr :team_id, :any
  attr :teams, :list

  # The question before a test that needs an answer. It opens as it renders (AskDialog),
  # and its fields go with the "test" event; Cancel or Escape sends "close_dialog".
  # ignore_attributes keeps it open when the page changes under it, as when another
  # test finishes.
  defp test_dialog(%{service: "email"} = assigns) do
    ~H"""
    <.confirm_dialog
      id="test-email-dialog"
      phx-hook="AskDialog"
      phx-mounted={JS.ignore_attributes(["open"])}
      data-confirm-event="test"
      data-cancel-event="close_dialog"
      question="Send a test email?"
      body="It comes from noreply@sarduty.com."
      action="Send test email"
    >
      <input type="hidden" name="service" value="email" />
      <div class="confirm-dialog-field">
        <label for="test-email-to">To</label>
        <input type="email" id="test-email-to" name="to" value={@email_to} autocomplete="off" />
      </div>
    </.confirm_dialog>
    """
  end

  defp test_dialog(%{service: "texts"} = assigns) do
    ~H"""
    <.confirm_dialog
      id="test-texts-dialog"
      phx-hook="AskDialog"
      phx-mounted={JS.ignore_attributes(["open"])}
      data-confirm-event="test"
      data-cancel-event="close_dialog"
      question="Send a test text?"
      body={texts_body()}
      action="Send test text"
    >
      <input type="hidden" name="service" value="texts" />
      <div class="confirm-dialog-field">
        <label for="test-texts-to">To</label>
        <input
          type="tel"
          id="test-texts-to"
          name="to"
          value={@text_to}
          placeholder="Mobile number"
          autocomplete="off"
        />
      </div>
    </.confirm_dialog>
    """
  end

  defp test_dialog(%{service: "d4h"} = assigns) do
    ~H"""
    <.confirm_dialog
      id="test-d4h-dialog"
      phx-hook="AskDialog"
      phx-mounted={JS.ignore_attributes(["open"])}
      data-confirm-event="test"
      data-cancel-event="close_dialog"
      question="Check a team's key?"
      body="It reads who the key belongs to. Nothing changes."
      action="Check key"
    >
      <input type="hidden" name="service" value="d4h" />
      <div class="confirm-dialog-field">
        <label for="test-d4h-team">Team</label>
        <.combobox
          id="test-d4h-team"
          name="team_id"
          value={@team_id}
          options={Enum.map(@teams, &{&1.name, &1.id})}
          placeholder="Pick a team"
        />
      </div>
    </.confirm_dialog>
    """
  end

  defp texts_body do
    case Twilio.from_number() do
      nil -> "It comes from SAR Duty's login number."
      from -> "It comes from #{Service.Phone.format(from)}, SAR Duty's login number."
    end
  end

  defp apple_detail do
    case Application.get_env(:sarduty, :apple_pass, [])[:certificate] do
      pem when is_binary(pem) and pem != "" ->
        expires = Service.ApplePass.certificate_expires_on(pem)
        "certificate expires #{Service.Format.day_in_year(expires, ~D[1970-01-01])}"

      _ ->
        "Apple"
    end
  end

  def handle_event("ask", %{"service" => service}, socket) when service in @asks,
    do: {:noreply, assign(socket, asking: service)}

  def handle_event("close_dialog", _params, socket), do: {:noreply, assign(socket, asking: nil)}

  def handle_event("test", %{"service" => service} = params, socket) when service in @runs do
    socket = assign(socket, asking: nil)

    if service in socket.assigns.running do
      {:noreply, socket}
    else
      user = socket.assigns.current_user

      {:noreply,
       socket
       |> remember(service, params)
       |> update(:running, &MapSet.put(&1, service))
       |> start_async({:test, service}, fn -> TestIntegration.call(service, params, user) end)}
    end
  end

  # What was typed is there again the next time the dialog opens.
  defp remember(socket, "email", params), do: assign(socket, email_to: params["to"])
  defp remember(socket, "texts", params), do: assign(socket, text_to: params["to"])
  defp remember(socket, "d4h", params), do: assign(socket, team_id: params["team_id"])
  defp remember(socket, _service, _params), do: socket

  def handle_async({:test, service}, result, socket) do
    socket =
      socket
      |> update(:running, &MapSet.delete(&1, service))
      |> assign_last_tests()

    case result do
      {:ok, {:ok, _outcome, message}} ->
        {:noreply, put_flash(socket, :info, message)}

      {:ok, {:error, _outcome, message}} ->
        {:noreply, put_flash(socket, :error, message)}

      {:exit, reason} ->
        {:noreply, put_flash(socket, :error, "The test stopped. #{inspect(reason)}")}
    end
  end
end
