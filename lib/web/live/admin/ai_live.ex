defmodule Web.Admin.AILive do
  use Web, :live_view_app_layout

  alias App.Adapter.Claude
  alias App.AI.Models
  alias App.Model.AIAsk
  alias App.Model.AISettings
  alias App.Operation.AskAI
  alias App.Operation.SetAISettings
  alias Service.Format

  @limit 50

  # Adminland › AI writing (docs/ai-writing.md): who gets it, which Claude model, and the
  # monthly budget, then this month's spend by team and by person, and the newest asks.
  # Everything is summed from ai_asks. Dollars show here only, never to a team.
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "AI writing", limit: @limit, configured: Claude.configured?())
     |> assign_settings(AISettings.get())
     |> assign_usage()}
  end

  defp assign_settings(socket, settings) do
    assign(socket,
      settings: settings,
      form: to_form(form_params(settings), as: "settings")
    )
  end

  defp form_params(settings),
    do: %{
      "access" => settings.access,
      "model" => settings.model,
      "monthly_budget" => div(settings.monthly_budget_cents, 100)
    }

  defp assign_usage(socket) do
    now = DateTime.utc_now()
    summary = AIAsk.month_summary(now)

    assign(socket,
      now: now,
      spent: AIAsk.month_cost_microdollars(now),
      teams: summary.teams,
      people: summary.people,
      asks: AIAsk.get_recent(@limit)
    )
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case SetAISettings.call(params, socket.assigns.current_user) do
      {:ok, settings} ->
        {:noreply,
         socket |> assign_settings(settings) |> put_flash(:info, "AI writing settings saved.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         socket
         |> assign(form: to_form(params, as: "settings"))
         |> put_flash(:error, "Enter the budget in whole dollars.")}

      {:error, :not_allowed} ->
        {:noreply, put_flash(socket, :error, "Only a SAR Duty admin can change this.")}
    end
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">AI writing</h1>
    <p class="lead max-w-3xl">
      Team admins describe a report and AI writes its query. Requests go to Anthropic's
      Claude API in the US, with the team's field names and never its records.
    </p>
    <.banner :if={!@configured} id="ai-not-set-up" title="Not set up here" class="mb-6">
      <p>Set ANTHROPIC_API_KEY to turn on AI writing on this server.</p>
    </.banner>

    <div class="content-wrapper">
      <section class="content-1/3" aria-labelledby="ai-settings-title">
        <h2 id="ai-settings-title" class="heading">Settings</h2>
        <.form for={@form} id="ai-settings" phx-submit="save">
          <.input
            field={@form[:access]}
            type="select"
            label="Who gets it"
            options={[
              {"Nobody", "off"},
              {"SAR Duty admins only", "admins"},
              {"Every team admin", "everyone"}
            ]}
          />
          <.input
            field={@form[:model]}
            type="select"
            label="Model"
            options={Enum.map(Models.all(), &{model_label(&1), &1.id})}
          />
          <.input
            field={@form[:monthly_budget]}
            type="number"
            label="Monthly budget in US dollars"
            min="0"
            step="1"
          >
            Asks stop for every team once this month's cost reaches it.
          </.input>
          <.button id="ai-settings-save" variant={:success} phx-disable-with="Saving…">
            Save
          </.button>
        </.form>
      </section>

      <section class="content-2/3" aria-labelledby="ai-month-title">
        <h2 id="ai-month-title" class="heading">This month</h2>
        <p id="ai-month-spent" class="mb-2">
          {Format.money(dollars(@spent))} of {Format.money(div(@settings.monthly_budget_cents, 100))} · {Format.count(
            Enum.sum(Enum.map(@teams, & &1.asks)),
            one: "%d ask",
            many: "%d asks"
          )}
        </p>
        <p :if={paused?(@spent, @settings)} id="ai-paused" class="warning-text mb-2">
          Paused: this month's asks reached the budget.
        </p>
        <p class="hint mb-6">
          {AskAI.asks_per_day()} asks a team a day at most. Months and days are BC time.
        </p>

        <h3 class="heading">By team</h3>
        <.table id="ai-teams" rows={@teams} row_id={&"ai-team-#{&1.id}"}>
          <:col :let={row} label="Team">{row.name}</:col>
          <:col :let={row} label="Asks" class="text-right">{Format.number(row.asks)}</:col>
          <:col :let={row} label="Tokens in" class="text-right">{Format.number(row.input)}</:col>
          <:col :let={row} label="From cache" class="text-right">
            {Format.number(row.cache_read)}
          </:col>
          <:col :let={row} label="Tokens out" class="text-right">{Format.number(row.output)}</:col>
          <:col :let={row} label="Cost" class="text-right">{Format.money(dollars(row.cost))}</:col>
        </.table>
        <.hint :if={@teams == []}>No asks this month.</.hint>

        <h3 class="heading mt-8">By person</h3>
        <.table id="ai-people" rows={@people} row_id={&"ai-person-#{&1.id}-#{&1.team}"}>
          <:col :let={row} label="Account">{row.email || "Deleted account"}</:col>
          <:col :let={row} label="Team">{row.team}</:col>
          <:col :let={row} label="Asks" class="text-right">{Format.number(row.asks)}</:col>
          <:col :let={row} label="Cost" class="text-right">{Format.money(dollars(row.cost))}</:col>
        </.table>
        <.hint :if={@people == []}>No asks this month.</.hint>
      </section>
    </div>

    <h2 class="heading mt-8">Newest asks</h2>
    <.table id="ai-asks" rows={@asks} row_id={&"ai-ask-#{&1.id}"} class="table-striped">
      <:col :let={ask} label="When" class="whitespace-nowrap">
        {Format.month_day_time(ask.asked_at, AIAsk.timezone())}
      </:col>
      <:col :let={ask} label="Team">{ask.team.name}</:col>
      <:col :let={ask} label="Account">{ask.user && ask.user.email}</:col>
      <:col :let={ask} label="Ask">
        {ask.ask}
        <.hint>{Models.name(ask.model)} · {outcome(ask.outcome)}</.hint>
      </:col>
      <:col :let={ask} label="Tokens" class="whitespace-nowrap">
        {Format.number(ask.input_tokens + ask.cache_write_tokens + ask.cache_read_tokens)} in
        <.hint>
          {Format.number(ask.cache_read_tokens)} from cache · {Format.number(ask.output_tokens)} out
        </.hint>
      </:col>
      <:col :let={ask} label="Cost" class="text-right">
        {Format.money(dollars(ask.cost_microdollars))}
      </:col>
      <:col :let={ask} label="Took" class="whitespace-nowrap">
        {ask.duration_ms && Format.run_time(ask.duration_ms)}
      </:col>
    </.table>
    <.hint :if={@asks == []}>No asks yet.</.hint>
    <.hint :if={length(@asks) == @limit}>The newest {@limit}.</.hint>
    """
  end

  defp model_label(model),
    do:
      "#{model.name}: #{Format.money(model.input)} in, #{Format.money(model.output)} out per million tokens"

  defp dollars(microdollars), do: (microdollars || 0) |> Decimal.new() |> Decimal.div(1_000_000)

  defp paused?(spent, settings), do: spent >= settings.monthly_budget_cents * 10_000

  defp outcome(:used), do: "used"
  defp outcome(:unchanged), do: "nothing changed"
  defp outcome(:refused_by_checks), do: "failed SAR Duty's checks"
  defp outcome(:refused), do: "declined"
  defp outcome(:failed), do: "failed"
end
