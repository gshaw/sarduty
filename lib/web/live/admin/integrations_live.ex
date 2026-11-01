defmodule Web.Admin.IntegrationsLive do
  use Web, :live_view_app_layout

  alias App.Model.Event
  alias App.Model.Team
  alias App.Operation.TestIntegration
  alias App.Worker.IntegrationTestWorker

  # Adminland › Integrations (#789): a row per service SAR Duty depends on, its last
  # test, and a button that makes one real call. A test runs in start_async, since some
  # wait seconds for an answer; the toast says how it went and the row's Last test keeps
  # the outcome. The Wallet tests are links to Web.Admin.IntegrationPassController.
  def mount(_params, _session, socket) do
    teams = Team.get_all() |> Enum.sort_by(&String.downcase(&1.name))

    {:ok,
     socket
     |> assign(page_title: "Integrations", teams: teams, running: MapSet.new())
     |> assign(email_to: socket.assigns.current_user.email, text_to: "", team_id: nil)
     |> assign_last_tests()}
  end

  defp assign_last_tests(socket),
    do: assign(socket, last: Event.get_last_by(:integration_tested, "service"))

  @doc "SAR Duty's own parts, then the services it calls: `{key, name, service, used for}`."
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
         {"d4h", "D4H", "Each team's key",
          "Everything a team reads and sends; Records teams too"},
         {"maps", "Maps", "Mapbox", "Maps on activities and places, and place search"},
         {"health", "Health checks", "Healthchecks.io",
          "Alerts when the nightly refresh or the D4H sync is late"},
         {"apple", "Apple Wallet", apple_service(), "ID cards on iPhones"},
         {"google", "Google Wallet", "Google", "ID cards on Android phones"}
       ]}
    ]

  def render(assigns) do
    ~H"""
    <h1 class="title">Integrations</h1>
    <p class="mb-4 max-w-3xl">
      Each test makes one real call to the service, and is saved in Events.
    </p>
    <section :for={{group, services} <- groups()} id={"integrations-#{group_id(group)}"}>
      <h2 class="subheading">{group}</h2>
      <ul class="integration-list">
        <li
          :for={{key, name, service, used_for} <- services}
          id={"integration-#{key}"}
          class="integration-row"
        >
          <div class="integration-name" title={used_for}>
            <span class="font-semibold">{name}</span>
            <span class="hint">· {service}</span>
          </div>
          <.last_test id={"integration-#{key}-last"} event={@last[key]} />
          <div class="integration-test">
            <.spinner
              :if={key in @running}
              id={"integration-#{key}-running"}
              class="text-sm text-link"
            >
              Testing
            </.spinner>
            <.test_form
              :if={key not in @running}
              key={key}
              email_to={@email_to}
              text_to={@text_to}
              team_id={@team_id}
              teams={@teams}
            />
          </div>
        </li>
      </ul>
    </section>
    """
  end

  defp group_id(group), do: group |> String.downcase() |> String.replace(" ", "-")

  attr :id, :string, required: true
  attr :event, :any, required: true

  defp last_test(%{event: nil} = assigns),
    do: ~H"""
    <span id={@id} class="integration-status text-text-muted">Never</span>
    """

  defp last_test(assigns) do
    assigns = assign(assigns, outcome: assigns.event.data["outcome"])

    ~H"""
    <span
      id={@id}
      class={["integration-status", outcome_class(@outcome)]}
      title={Service.Format.month_day_time(@event.occurred_at, "America/Vancouver")}
    >
      <.icon name={if ok?(@outcome), do: "circle-check", else: "circle-alert"} size={:sm} />
      {outcome_label(@outcome)} · {Service.Format.month_day_time(
        @event.occurred_at,
        "America/Vancouver"
      )}
    </span>
    """
  end

  defp ok?(outcome), do: outcome in ["sent", "works"]

  defp outcome_class(outcome) do
    cond do
      ok?(outcome) -> "text-success-text"
      outcome == "running" -> "text-text-muted"
      true -> "text-danger-text"
    end
  end

  defp outcome_label("running"), do: "Didn't finish"
  defp outcome_label(outcome), do: String.capitalize(outcome)

  attr :key, :string, required: true
  attr :email_to, :string
  attr :text_to, :string
  attr :team_id, :any
  attr :teams, :list

  defp test_form(%{key: "email"} = assigns) do
    ~H"""
    <form id="test-email" phx-submit="test" class="integration-form">
      <input type="hidden" name="service" value="email" />
      <input
        type="email"
        name="to"
        id="test-email-to"
        value={@email_to}
        aria-label="Send to"
        placeholder="Email address"
        class="input-sm"
      />
      <.button size={:sm}>Send test email</.button>
    </form>
    """
  end

  defp test_form(%{key: "texts"} = assigns) do
    ~H"""
    <form id="test-texts" phx-submit="test" class="integration-form">
      <input type="hidden" name="service" value="texts" />
      <input
        type="tel"
        name="to"
        id="test-texts-to"
        value={@text_to}
        aria-label="Send to"
        placeholder="Mobile number"
        class="input-sm"
      />
      <.button size={:sm}>Send test text</.button>
    </form>
    """
  end

  defp test_form(%{key: "d4h"} = assigns) do
    ~H"""
    <form id="test-d4h" phx-submit="test" class="integration-form">
      <input type="hidden" name="service" value="d4h" />
      <.combobox
        id="test-d4h-team"
        name="team_id"
        value={@team_id}
        options={Enum.map(@teams, &{&1.name, &1.id})}
        placeholder="Pick a team"
        size={:sm}
        aria-label="Team"
      />
      <.button size={:sm}>Check key</.button>
    </form>
    """
  end

  defp test_form(%{key: "apple"} = assigns) do
    ~H"""
    <.button id="test-apple" size={:sm} href={~p"/admin/integrations/apple-pass"}>
      Download test pass
    </.button>
    """
  end

  defp test_form(%{key: "google"} = assigns) do
    ~H"""
    <.button id="test-google" size={:sm} href={~p"/admin/integrations/google-pass"}>
      Add test pass
    </.button>
    """
  end

  defp test_form(assigns) do
    ~H"""
    <.button id={"test-#{@key}"} type="button" size={:sm} phx-click="test" phx-value-service={@key}>
      {button_label(@key)}
    </.button>
    """
  end

  defp button_label("website"), do: "Check website"
  defp button_label("jobs"), do: "Run test jobs"
  defp button_label("backups"), do: "Check backup"
  defp button_label("errors"), do: "Send test error"
  defp button_label("maps"), do: "Check token"
  defp button_label("health"), do: "Send test ping"

  defp apple_service do
    case Application.get_env(:sarduty, :apple_pass, [])[:certificate] do
      pem when is_binary(pem) and pem != "" ->
        expires = Service.ApplePass.certificate_expires_on(pem)
        "certificate to #{Service.Format.day_in_year(expires, ~D[1970-01-01])}"

      _ ->
        "not set up here"
    end
  end

  def handle_event("test", %{"service" => service} = params, socket)
      when service in [
             "website",
             "jobs",
             "backups",
             "email",
             "texts",
             "errors",
             "d4h",
             "maps",
             "health"
           ] do
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

  # What was typed stays in the box for the next test.
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
