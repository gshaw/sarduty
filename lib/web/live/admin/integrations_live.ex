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

  @doc "Each row: its key, name, the service behind it, and what SAR Duty uses it for."
  def rows,
    do: [
      {"website", "Website", "#{Web.Endpoint.host()}/health",
       "Fly's check every 15 seconds: the app answers and its database replies"},
      {"jobs", "Background jobs", "Oban, #{length(IntegrationTestWorker.queues())} queues",
       "Reminders, emails, passes, and the D4H sync and refresh"},
      {"backups", "Backups", "Litestream to Cloudflare R2",
       "A copy of the database, kept up to the second"},
      {"email", "Email", "Cloudflare", "Login codes, reminders, replies, letters, team emails"},
      {"texts", "Texts", "Twilio", "Login codes by text"},
      {"errors", "Errors", "Honeybadger", "Errors on pages and in jobs"},
      {"d4h", "D4H", "Each team's access key", "Everything a team reads and sends"},
      {"maps", "Maps", "Mapbox", "Maps on activities and places, place search"},
      {"health", "Health checks", "Healthchecks.io",
       "Alerts when the nightly refresh or the D4H sync is late"},
      {"apple", "Apple Wallet", "Apple", "ID cards on iPhones"},
      {"google", "Google Wallet", "Google", "ID cards on Android phones"}
    ]

  def render(assigns) do
    ~H"""
    <h1 class="title">Integrations</h1>
    <p class="mb-4 max-w-3xl">
      The services SAR Duty sends through. Each test sends one real email, text, or call, and is
      saved in Events.
    </p>
    <.table id="integrations" rows={rows()} row_id={fn {key, _, _, _} -> "integration-#{key}" end}>
      <:col :let={{_key, name, service, _used_for}} label="Service">
        <div class="font-semibold">{name}</div>
        <.hint>{service}</.hint>
      </:col>
      <:col :let={{key, _name, _service, used_for}} label="Used for">
        {used_for}<span :if={key == "apple"} id="apple-expires">. {apple_expiry()}</span>
      </:col>
      <:col :let={{key, _name, _service, _used_for}} label="Last test" class="whitespace-nowrap">
        <.last_test id={"integration-#{key}-last"} event={@last[key]} />
      </:col>
      <:col :let={{key, _name, _service, _used_for}} label="Test" class="w-px">
        <.spinner :if={key in @running} id={"integration-#{key}-running"} class="text-sm text-link">
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
      </:col>
    </.table>
    <p class="hint mt-4">Records teams test through D4H: Records is a D4H host.</p>
    """
  end

  attr :id, :string, required: true
  attr :event, :any, required: true

  defp last_test(%{event: nil} = assigns),
    do: ~H"""
    <span id={@id} class="text-text-muted">Never</span>
    """

  defp last_test(assigns) do
    ~H"""
    <span id={@id}>
      <span class={outcome_class(@event.data["outcome"])}>{outcome_label(@event.data["outcome"])}</span>
      <.hint>{Service.Format.month_day_time(@event.occurred_at, "America/Vancouver")}</.hint>
    </span>
    """
  end

  defp outcome_class(outcome) when outcome in ["sent", "works"], do: "text-success-text"
  defp outcome_class("running"), do: "text-text-muted"
  defp outcome_class(_outcome), do: "text-danger-text"

  defp outcome_label("running"), do: "Didn't finish"
  defp outcome_label(outcome), do: String.capitalize(outcome)

  attr :key, :string, required: true
  attr :email_to, :string
  attr :text_to, :string
  attr :team_id, :any
  attr :teams, :list

  defp test_form(%{key: "email"} = assigns) do
    ~H"""
    <form id="test-email" phx-submit="test" class="flex items-center gap-2 whitespace-nowrap">
      <input type="hidden" name="service" value="email" />
      <input
        type="email"
        name="to"
        id="test-email-to"
        value={@email_to}
        aria-label="To"
        class="w-full max-w-xs"
      />
      <.button size={:sm}>Send test email</.button>
    </form>
    """
  end

  defp test_form(%{key: "texts"} = assigns) do
    ~H"""
    <form id="test-texts" phx-submit="test" class="flex items-center gap-2 whitespace-nowrap">
      <input type="hidden" name="service" value="texts" />
      <input
        type="tel"
        name="to"
        id="test-texts-to"
        value={@text_to}
        aria-label="To"
        placeholder="Mobile number"
        class="w-full max-w-xs"
      />
      <.button size={:sm}>Send test text</.button>
    </form>
    """
  end

  defp test_form(%{key: "d4h"} = assigns) do
    ~H"""
    <form id="test-d4h" phx-submit="test" class="flex items-center gap-2 whitespace-nowrap">
      <input type="hidden" name="service" value="d4h" />
      <div class="w-full max-w-xs">
        <.combobox
          id="test-d4h-team"
          name="team_id"
          value={@team_id}
          options={Enum.map(@teams, &{&1.name, &1.id})}
          prompt="Team"
          aria-label="Team"
        />
      </div>
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
    <.button
      id={"test-#{@key}"}
      type="button"
      size={:sm}
      phx-click="test"
      phx-value-service={@key}
    >
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

  defp apple_expiry do
    case Application.get_env(:sarduty, :apple_pass, [])[:certificate] do
      pem when is_binary(pem) and pem != "" ->
        "The certificate expires #{Service.Format.day_in_year(Service.ApplePass.certificate_expires_on(pem), ~D[1970-01-01])}"

      _ ->
        "Not set up on this server"
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
