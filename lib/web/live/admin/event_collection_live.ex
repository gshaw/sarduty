defmodule Web.Admin.EventCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.FilterBar

  alias App.Model.Event
  alias App.Model.Team
  alias App.ViewModel.EventFilterViewModel

  @limit 200

  # Signs of someone guessing or flooding, for the top IPs list. Top accounts counts the
  # wrong codes and blocks against one email or number.
  @account_kinds [:login_code_missed, :login_blocked]
  @attack_kinds [
    :login_code_missed,
    :login_code_limited,
    :login_blocked,
    :verify_limit_reached,
    :verify_guess_found,
    :team_signup_failed
  ]

  def mount(_params, _session, socket) do
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(page_title: "Events", teams: Team.get_all_real(), now: now, limit: @limit)
      |> assign(last_round: Event.get_last(:d4h_sync_round))
      |> assign(last_run: Event.get_last(:d4h_refresh_run))
      |> assign(rate_limited: Event.count_since(:d4h_rate_limited, DateTime.add(now, -1, :day)))
      |> assign(
        sync_failures:
          Event.count_since(:d4h_team_sync, DateTime.add(now, -1, :day),
            data: %{outcome: "failed"}
          )
      )
      |> assign_logins(DateTime.add(now, -7, :day))

    {:ok, socket}
  end

  defp assign_logins(socket, since) do
    assign(socket,
      logins: Event.count_since(:logged_in, since),
      passkey_logins: Event.count_since(:logged_in, since, data: %{via: "passkey"}),
      misses: Event.count_since(:login_code_missed, since),
      blocks: Event.count_since(:login_blocked, since),
      top_ips: Event.get_top_ips(@attack_kinds, since, 10),
      top_accounts: Event.get_top_accounts(@account_kinds, since, 10)
    )
  end

  def handle_params(params, _uri, socket) do
    case EventFilterViewModel.validate(params) do
      {:ok, filter, changeset} ->
        events = filter |> EventFilterViewModel.to_query() |> Event.get_recent(@limit)

        {:noreply,
         assign(socket, events: events, filter: filter, form: to_form(changeset, as: "form"))}

      {:error, _changeset} ->
        raise Web.Status.NotFound
    end
  end

  def handle_event("change", %{"form" => params}, socket) do
    case EventFilterViewModel.validate(params) do
      {:ok, filter, _changeset} ->
        path = ~p"/admin/events?#{EventFilterViewModel.to_params(filter)}"
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _changeset} ->
        raise Web.Status.NotFound
    end
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">Events</h1>
    <h2 class="heading">D4H sync</h2>
    <dl id="sync-summary" class="mb-8 max-w-3xl">
      <dt>Last sync round</dt>
      <dd id="last-round">{run_summary(@last_round, @now)}</dd>
      <dt>Last nightly refresh</dt>
      <dd id="last-run">{run_summary(@last_run, @now)}</dd>
      <dt>In the last 24 hours</dt>
      <dd id="last-day">
        {Service.Format.count(@sync_failures, one: "%d failed sync", many: "%d failed syncs")}, {Service.Format.count(
          @rate_limited,
          one: "%d D4H rate limit",
          many: "%d D4H rate limits"
        )}
      </dd>
    </dl>

    <h2 class="heading">Logins</h2>
    <dl id="login-summary" class="mb-4 max-w-3xl">
      <dt>In the last 7 days</dt>
      <dd id="last-week">
        {Service.Format.count(@logins, one: "%d login", many: "%d logins")}, {@passkey_logins} with a passkey, {Service.Format.count(
          @misses,
          one: "%d wrong code",
          many: "%d wrong codes"
        )}, {Service.Format.count(@blocks, one: "%d block", many: "%d blocks")}
      </dd>
    </dl>
    <div class="mb-8 grid items-start gap-8 md:grid-cols-2">
      <section :if={@top_ips != []} id="top-ips-list">
        <h3 class="subheading mb-0">Top IPs</h3>
        <.hint>Wrong codes, limits, blocks, and failed sign-ups. An IPv6 /64 counts as one.</.hint>
        <.table
          id="top-ips"
          rows={Enum.with_index(@top_ips, 1)}
          row_id={fn {_ip_count, rank} -> "top-ip-#{rank}" end}
          class="table-striped"
        >
          <:col :let={{{ip, _count}, _rank}} label="IP">
            <.a patch={~p"/admin/events?#{[ip: ip]}"}>{ip}</.a>
          </:col>
          <:col :let={{{_ip, count}, _rank}} label="Events">{count}</:col>
        </.table>
      </section>
      <section :if={@top_accounts != []} id="top-accounts-list">
        <h3 class="subheading mb-0">Top accounts</h3>
        <.hint>Wrong codes and blocks, for each email or number.</.hint>
        <.table
          id="top-accounts"
          rows={Enum.with_index(@top_accounts, 1)}
          row_id={fn {_account, rank} -> "top-account-#{rank}" end}
          class="table-striped"
        >
          <:col :let={{{who, shown, _count}, _rank}} label="Email or number">
            <.account_link who={who} shown={shown} path={~p"/admin/events?#{[who: shown || who]}"} />
          </:col>
          <:col :let={{{_who, _shown, count}, _rank}} label="Events">{count}</:col>
        </.table>
      </section>
    </div>

    <h2 class="heading">Latest events</h2>
    <.filter_bar
      for={@form}
      id="event_filter_form"
      count={Service.Format.count(length(@events), one: "%d event", many: "%d events")}
      clear={~p"/admin/events"}
      path_fn={&events_path(@filter, &1)}
    >
      <:search field={@form[:who]} placeholder="Email or number" />
      <:search field={@form[:ip]} placeholder="IP address" />
      <:filter field={@form[:kind]} label="Kind" options={EventFilterViewModel.kinds()} default="all" />
      <:filter
        field={@form[:team]}
        label="Team"
        options={EventFilterViewModel.teams(@teams)}
        default="all"
      />
    </.filter_bar>
    <.table id="events" rows={@events} row_id={&"event-#{&1.id}"} class="table-striped">
      <:col :let={event} label="When (UTC)" class="whitespace-nowrap">
        {Service.Format.month_day_time_seconds(event.occurred_at, "Etc/UTC")}
      </:col>
      <:col :let={event} label="Kind" class="whitespace-nowrap">
        {EventFilterViewModel.label(event.kind)}
      </:col>
      <:col :let={event} label="Team">{event.team && event.team.name}</:col>
      <:col :let={event} label="Took" class="whitespace-nowrap">
        {event.duration_ms && Service.Format.run_time(event.duration_ms)}
      </:col>
      <:col :let={event} label="From">
        <span :if={event.ip} title={event.user_agent}>{event.ip}</span>
      </:col>
      <:col :let={event} label="Details">
        <.account_link
          :if={event.who}
          who={event.who}
          shown={event.email_or_phone}
          path={events_path(@filter, who: event.email_or_phone || event.who)}
        />
        {details(event)}
      </:col>
    </.table>
    <.hint :if={length(@events) == @limit}>The newest {@limit}.</.hint>
    """
  end

  # The email or number typed, or the hash alone for an event from before they were kept.
  attr :who, :string, required: true
  attr :shown, :string, default: nil
  attr :path, :string, required: true

  defp account_link(assigns) do
    ~H"""
    <.a :if={@shown} patch={@path}>{@shown}</.a>
    <.a :if={!@shown} patch={@path} class="font-mono">{@who}</.a>
    """
  end

  defp events_path(filter, changes),
    do: ~p"/admin/events?#{EventFilterViewModel.to_params(Map.merge(filter, Map.new(changes)))}"

  defp run_summary(nil, _now), do: "None yet"

  defp run_summary(event, now) do
    teams = Service.Format.count(event.data["teams"] || 0, one: "%d team", many: "%d teams")
    ago = Service.Format.minutes_ago(event.occurred_at, now, "Etc/UTC")

    "#{ago}: #{teams} in #{event.duration_ms && Service.Format.run_time(event.duration_ms)}, #{event.data["outcome"]}"
  end

  # A task run in production (App.Ops) starts with the admin who ran it.
  defp details(%{kind: :prod_task, user: user, data: data}),
    do: [user && user.email, details(%{data: data})] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")

  # After the email, number, or hash, when there is one.
  defp details(%{who: who, data: data}) when is_binary(who) and data != %{},
    do: "· " <> details(%{who: nil, data: data})

  defp details(%{data: data}) do
    data
    |> Enum.sort()
    |> Enum.map_join(" · ", fn {key, value} -> "#{key}: #{value(value)}" end)
  end

  defp value(map) when is_map(map),
    do: map |> Enum.sort() |> Enum.map_join(", ", fn {key, n} -> "#{key} #{n}" end)

  defp value(list) when is_list(list), do: Enum.join(list, ", ")
  defp value(other), do: to_string(other)
end
