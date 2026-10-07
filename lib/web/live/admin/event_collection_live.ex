defmodule Web.Admin.EventCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.AdminTabs

  alias App.Model.Event
  alias App.Model.Team
  alias App.ViewModel.EventFilterViewModel

  @limit 200

  # Signs of someone guessing or flooding, for the top IPs list.
  @attack_kinds [
    :login_code_missed,
    :login_code_limited,
    :login_blocked,
    :verify_limit_reached,
    :team_signup_failed
  ]

  def mount(_params, _session, socket) do
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(page_title: "Events", teams: Team.get_all(), now: now, limit: @limit)
      |> assign(last_round: Event.get_last(:d4h_sync_round))
      |> assign(last_run: Event.get_last(:d4h_refresh_run))
      |> assign(rate_limited: Event.count_since(:d4h_rate_limited, DateTime.add(now, -1, :day)))
      |> assign(
        sync_failures:
          Event.count_since(:d4h_team_sync, DateTime.add(now, -1, :day), %{outcome: "failed"})
      )
      |> assign_logins(DateTime.add(now, -7, :day))

    {:ok, socket}
  end

  defp assign_logins(socket, since) do
    assign(socket,
      logins: Event.count_since(:logged_in, since),
      misses: Event.count_since(:login_code_missed, since),
      blocks: Event.count_since(:login_blocked, since),
      top_ips: Event.get_top_ips(@attack_kinds, since, 10)
    )
  end

  def handle_params(params, _uri, socket) do
    case EventFilterViewModel.validate(params) do
      {:ok, filter, changeset} ->
        events = filter |> EventFilterViewModel.to_query() |> Event.get_recent(@limit)
        {:noreply, assign(socket, events: events, form: to_form(changeset, as: "form"))}

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
    <h1 class="title">Admin</h1>
    <.admin_tabs current={:events} />
    <h2 class="heading">D4H sync</h2>
    <dl id="sync-summary" class="mb-p2 max-w-3xl">
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
    <dl id="login-summary" class="mb-p max-w-3xl">
      <dt>In the last 7 days</dt>
      <dd id="last-week">
        {Service.Format.count(@logins, one: "%d login", many: "%d logins")}, {Service.Format.count(
          @misses,
          one: "%d wrong code",
          many: "%d wrong codes"
        )}, {Service.Format.count(@blocks, one: "%d block", many: "%d blocks")}
      </dd>
    </dl>
    <.table
      :if={@top_ips != []}
      id="top-ips"
      rows={Enum.with_index(@top_ips, 1)}
      row_id={fn {_ip_count, rank} -> "top-ip-#{rank}" end}
      class="mb-p2 table-striped"
    >
      <:col :let={{{ip, _count}, _rank}} label="IP">
        <.a navigate={~p"/admin/events?#{[ip: ip]}"}>{ip}</.a>
      </:col>
      <:col :let={{{_ip, count}, _rank}} label="Wrong codes, limits, blocks, and failed sign-ups">
        {count}
      </:col>
    </.table>

    <h2 class="heading">Events</h2>
    <.form for={@form} id="event_filter_form" phx-change="change" class="filter-form">
      <.input label="Kind" field={@form[:kind]} type="select" options={EventFilterViewModel.kinds()} />
      <.input
        label="Team"
        field={@form[:team]}
        type="select"
        options={EventFilterViewModel.teams(@teams)}
      />
      <.input label="IP" field={@form[:ip]} phx-debounce="500" />
    </.form>
    <.table id="events" rows={@events} row_id={&"event-#{&1.id}"} class="table-striped">
      <:col :let={event} label="When (UTC)" class="whitespace-nowrap">
        {Service.Format.month_day_time_seconds(event.occurred_at, "Etc/UTC")}
      </:col>
      <:col :let={event} label="Kind" class="whitespace-nowrap">
        {EventFilterViewModel.label(event.kind)}
      </:col>
      <:col :let={event} label="Team">{event.team && event.team.name}</:col>
      <:col :let={event} label="Took" class="whitespace-nowrap">{took(event.duration_ms)}</:col>
      <:col :let={event} label="From">
        <span :if={event.ip} title={event.user_agent}>{event.ip}</span>
      </:col>
      <:col :let={event} label="Details">{details(event.data)}</:col>
    </.table>
    <.hint :if={@events == []}>No events.</.hint>
    <.hint :if={length(@events) == @limit}>The newest {@limit}.</.hint>
    """
  end

  defp run_summary(nil, _now), do: "None yet"

  defp run_summary(event, now) do
    teams = Service.Format.count(event.data["teams"] || 0, one: "%d team", many: "%d teams")
    ago = Service.Format.minutes_ago(event.occurred_at, now, "Etc/UTC")
    "#{ago}: #{teams} in #{took(event.duration_ms)}, #{event.data["outcome"]}"
  end

  defp took(nil), do: nil
  defp took(ms) when ms < 1000, do: "#{ms} ms"
  defp took(ms) when ms < 120_000, do: "#{Float.round(ms / 1000, 1)} s"
  defp took(ms), do: "#{Float.round(ms / 60_000, 1)} min"

  defp details(data) do
    data
    |> Enum.sort()
    |> Enum.map_join(" · ", fn {key, value} -> "#{key}: #{value(value)}" end)
  end

  defp value(map) when is_map(map),
    do: map |> Enum.sort() |> Enum.map_join(", ", fn {key, n} -> "#{key} #{n}" end)

  defp value(list) when is_list(list), do: Enum.join(list, ", ")
  defp value(other), do: to_string(other)
end
