defmodule Web.ActivityEquipmentLive do
  use Web, :live_view_app_layout

  alias App.Model.ChangeSetRow
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.Kit
  alias App.Operation.ChangeActivityEquipment

  # Adding equipment to an activity (#271). Items come from the last activity of the same
  # kind, from kits, or from a search, into a list with hours to check. Sending the list
  # writes them to D4H as equipment usages.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    Web.EquipmentItemLive.require_equipment!(team)
    activity = Web.ActivityLive.fetch_activity(team, id)

    if activity.deleted_at do
      {:ok, Web.ActivityLive.leave_deleted(socket, activity)}
    else
      last = EquipmentUsage.last_activity_with_equipment(activity)

      socket =
        socket
        |> assign(page_title: "Add equipment", activity: activity, lines: [], q: "", results: [])
        |> assign(kits: Kit.get_all(team.id), last: last)
        |> assign(last_usages: if(last, do: EquipmentUsage.for_activity(last), else: []))
        |> assign(default_minutes: default_minutes(activity))
        |> load_usages()

      {:ok, socket}
    end
  end

  # An item from a search starts at the activity's length.
  defp default_minutes(activity),
    do: max(Service.Convert.duration_to_minutes(activity.started_at, activity.finished_at), 0)

  defp load_usages(socket) do
    usages = EquipmentUsage.for_activity(socket.assigns.activity)
    used = MapSet.new(usages, & &1.equipment_item_id)
    assign(socket, usages: usages, used: used)
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item label={@activity.ref_id} path={~p"/teams/#{@current_team}/activities/#{@activity.id}"} />
      <:item label="Add equipment" />
    </.breadcrumbs>
    <h1 class="title">Add equipment</h1>
    <p class="lead">{@activity.title}</p>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <section :if={@last} id="equipment-same-as-last" class="mb-8">
          <h2 class="heading">Same as last {@activity.activity_kind}</h2>
          <p class="hint">
            {@last.title}, {Service.Format.date_short(@last.started_at, @current_team.timezone)}
          </p>
          <ul class="mb-4">
            <li :for={usage <- @last_usages}>{usage.equipment_item.title}</li>
          </ul>
          <.button id="equipment-add-last" type="button" size={:sm} phx-click="add-last">
            Add {Service.Format.count(length(@last_usages), one: "%d item", many: "%d items")}
          </.button>
        </section>

        <section id="equipment-kits" class="mb-8">
          <h2 class="heading">Kits</h2>
          <ul :if={@kits != []} class="action-list mb-4">
            <li :for={kit <- @kits}>
              <.button
                id={"equipment-add-kit-#{kit.id}"}
                type="button"
                size={:sm}
                variant={:secondary}
                phx-click="add-kit"
                phx-value-id={kit.id}
              >
                Add {kit.title}
              </.button>
              <span class="hint">
                {Service.Format.count(length(kit.kit_items), one: "%d item", many: "%d items")}
              </span>
            </li>
          </ul>
          <p class="hint">
            <.a navigate={~p"/teams/#{@current_team}/equipment/kits"}>
              {if @kits == [], do: "Add a kit", else: "Change kits"}
            </.a>
            for gear that goes out together.
          </p>
        </section>

        <section id="equipment-search">
          <h2 class="heading">Find an item</h2>
          <.item_search q={@q} results={@results} />
        </section>
      </aside>

      <main class="content-2/3">
        <section id="equipment-to-add" class="mb-8">
          <h2 class="heading">To add</h2>
          <.form
            :if={@lines != []}
            for={%{}}
            id="equipment-lines"
            phx-change="hours"
            phx-submit="send"
          >
            <.lines_table id="equipment-lines-table" lines={@lines} />
            <.form_actions>
              <.button id="equipment-send" variant={:success} phx-disable-with="Sending to D4H…">
                Add {Service.Format.count(length(@lines), one: "%d item", many: "%d items")} to D4H
              </.button>
            </.form_actions>
          </.form>
          <p :if={@lines == []} id="equipment-nothing-to-add" class="hint">
            Add items from the last {@activity.activity_kind}, a kit, or a search. Check the hours, then send them to D4H.
          </p>
        </section>

        <section id="equipment-on-activity">
          <h2 class="heading">On the activity · {length(@usages)}</h2>
          <.table
            :if={@usages != []}
            id="equipment-usages"
            rows={@usages}
            row_id={&"usage-#{&1.id}"}
            class="table-striped"
          >
            <:col :let={usage} label="Item">
              <.a navigate={~p"/teams/#{@current_team}/equipment/#{usage.equipment_item.id}"}>
                {usage.equipment_item.title}
              </.a>
            </:col>
            <:col :let={usage} label="Used" align="right" class="w-px whitespace-nowrap">
              {amount(usage)}
            </:col>
            <:col :let={usage} label="" class="w-px whitespace-nowrap">
              <.button
                id={"usage-remove-#{usage.id}"}
                type="button"
                size={:sm}
                variant={:danger}
                phx-click="remove-usage"
                phx-value-id={usage.id}
                data-confirm={"Remove #{usage.equipment_item.title} from this activity in D4H?"}
              >
                Remove
              </.button>
            </:col>
          </.table>
          <p :if={@usages == []} class="hint">D4H has no equipment on this activity.</p>
        </section>
      </main>
    </div>
    """
  end

  @doc "What a usage counted: hours for equipment, km for a vehicle, a count for a supply."
  def amount(%EquipmentUsage{minutes: minutes}) when is_integer(minutes) and minutes > 0,
    do: Service.Format.duration_as_hours_minutes_short(minutes)

  def amount(%EquipmentUsage{distance: km}) when is_integer(km) and km > 0, do: "#{km} km"
  def amount(%EquipmentUsage{used: used}) when is_integer(used) and used > 0, do: "#{used} used"
  def amount(%EquipmentUsage{}), do: ""

  attr :id, :string, required: true
  attr :lines, :list, required: true

  @doc """
  The items about to be added, each with an hours field when D4H counts hours for it.
  Shared with the kit form. Inputs are named `hours[item id]`.
  """
  def lines_table(assigns) do
    ~H"""
    <.table id={@id} rows={@lines} row_id={&"line-#{&1.item.id}"} class="table-striped">
      <:col :let={line} label="Item">
        {line.item.title} <span :if={line.item.kind} class="hint">{line.item.kind}</span>
      </:col>
      <:col :let={line} label="Hours" class="w-px whitespace-nowrap">
        <input
          :if={EquipmentItem.takes_hours?(line.item)}
          type="number"
          id={"hours-#{line.item.id}"}
          name={"hours[#{line.item.id}]"}
          value={line.hours}
          min="0"
          step="0.5"
          class="w-16"
          aria-label={"Hours for #{line.item.title}"}
        />
        <span :if={!EquipmentItem.takes_hours?(line.item)} class="hint">
          {if line.item.item_type == "vehicle", do: "Not counted for vehicles", else: "Not counted"}
        </span>
      </:col>
      <:col :let={line} label="" class="w-px whitespace-nowrap">
        <.button
          id={"line-remove-#{line.item.id}"}
          type="button"
          size={:sm}
          variant={:secondary}
          phx-click="remove-line"
          phx-value-id={line.item.id}
        >
          Remove
        </.button>
      </:col>
    </.table>
    """
  end

  attr :q, :string, required: true
  attr :results, :list, required: true

  @doc "A search box for items, with an add button for each one found. Shared with the kit form."
  def item_search(assigns) do
    ~H"""
    <.form for={%{}} id="item-search-form" phx-change="search" phx-submit="search">
      <.input
        id="item-search"
        name="q"
        value={@q}
        label="Search"
        placeholder="Name, barcode, or serial"
        phx-debounce="200"
        autocomplete="off"
      />
    </.form>
    <ul :if={@results != []} id="item-search-results" class="action-list">
      <li :for={item <- @results}>
        <.button
          id={"item-add-#{item.id}"}
          type="button"
          size={:sm}
          variant={:secondary}
          phx-click="add-item"
          phx-value-id={item.id}
        >
          Add
        </.button>
        {item.title} <span :if={item.kind} class="hint">{item.kind}</span>
      </li>
    </ul>
    <p :if={@q != "" and @results == []} class="hint">No items match "{@q}".</p>
    """
  end

  @doc """
  `lines` with `new` added at the end, each `{item, minutes}`. Items already in `lines`,
  or in `skip` (ids of items to leave out), aren't added twice.
  """
  def add_lines(lines, new, skip \\ MapSet.new()) do
    have = MapSet.new(lines, & &1.item.id)

    added =
      new
      |> Enum.uniq_by(fn {item, _minutes} -> item.id end)
      |> Enum.reject(fn {item, _minutes} ->
        MapSet.member?(have, item.id) or MapSet.member?(skip, item.id)
      end)
      |> Enum.map(fn {item, minutes} ->
        %{item: item, hours: Service.Convert.minutes_to_hours(minutes)}
      end)

    lines ++ added
  end

  @doc "`lines` with the hours typed in `hours`, a map of item id (as text) to hours."
  def put_hours(lines, hours) do
    Enum.map(lines, fn line ->
      case Map.fetch(hours, Integer.to_string(line.item.id)) do
        {:ok, text} -> %{line | hours: text}
        :error -> line
      end
    end)
  end

  def remove_line(lines, id), do: Enum.reject(lines, &(Integer.to_string(&1.item.id) == id))

  @doc "Items found for `q`, without the ones whose ids are in `skip`."
  def search(team, q, skip),
    do: team.id |> EquipmentItem.search(q) |> Enum.reject(&MapSet.member?(skip, &1.id))

  def handle_event("add-last", _params, socket) do
    new =
      for usage <- socket.assigns.last_usages, EquipmentItem.in_service?(usage.equipment_item) do
        {usage.equipment_item, usage.minutes || socket.assigns.default_minutes}
      end

    {:noreply, add(socket, new)}
  end

  def handle_event("add-kit", %{"id" => id}, socket) do
    kit = Kit.find!(socket.assigns.current_team, id)

    new =
      for line <- kit.kit_items, EquipmentItem.in_service?(line.equipment_item) do
        {line.equipment_item, line.minutes}
      end

    {:noreply, add(socket, new)}
  end

  def handle_event("add-item", %{"id" => id}, socket) do
    item = EquipmentItem.find!(socket.assigns.current_team, id)
    {:noreply, add(socket, [{item, socket.assigns.default_minutes}])}
  end

  def handle_event("remove-line", %{"id" => id}, socket),
    do: {:noreply, assign(socket, lines: remove_line(socket.assigns.lines, id))}

  def handle_event("search", %{"q" => q}, socket) do
    skip = MapSet.union(socket.assigns.used, MapSet.new(socket.assigns.lines, & &1.item.id))
    results = search(socket.assigns.current_team, q, skip)
    {:noreply, assign(socket, q: q, results: results)}
  end

  def handle_event("hours", params, socket),
    do: {:noreply, assign(socket, lines: put_hours(socket.assigns.lines, params["hours"] || %{}))}

  def handle_event("send", params, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns
    lines = put_hours(socket.assigns.lines, params["hours"] || %{})

    lines =
      Enum.map(lines, &%{item: &1.item, minutes: Service.Convert.hours_to_minutes(&1.hours)})

    case ChangeActivityEquipment.add(team, activity, lines, user, DateTime.utc_now()) do
      {:ok, rows} ->
        socket =
          socket
          |> put_flash(flash_kind(rows), result_text(rows, "added to"))
          |> push_navigate(to: ~p"/teams/#{team}/activities/#{activity.id}")

        {:noreply, socket}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  def handle_event("remove-usage", %{"id" => id}, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns

    case Enum.find(socket.assigns.usages, &(Integer.to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      usage ->
        case ChangeActivityEquipment.remove(team, activity, usage, user, DateTime.utc_now()) do
          {:ok, rows} ->
            {:noreply,
             socket
             |> put_flash(flash_kind(rows), result_text(rows, "removed from"))
             |> load_usages()}

          {:error, text} ->
            {:noreply, put_flash(socket, :error, text)}
        end
    end
  end

  defp add(socket, new) do
    lines = add_lines(socket.assigns.lines, new, socket.assigns.used)

    results =
      Enum.reject(socket.assigns.results, fn item ->
        Enum.any?(lines, &(&1.item.id == item.id))
      end)

    assign(socket, lines: lines, results: results)
  end

  defp flash_kind(rows),
    do: if(Enum.all?(rows, &(&1.status == :applied)), do: :info, else: :error)

  @doc """
  What happened, as one message: "3 items added to D4H." and then each row D4H didn't
  take, with why.
  """
  def result_text(rows, verb) do
    applied = Enum.count(rows, &(&1.status == :applied))
    done = Service.Format.count(applied, one: "%d item", many: "%d items") <> " #{verb} D4H."

    rows
    |> Enum.reject(&(&1.status == :applied))
    |> Enum.map(&"#{row_title(&1)}: #{&1.error}")
    |> then(&Enum.join([done | &1], " "))
  end

  defp row_title(%ChangeSetRow{new_value: %{"title" => title}}), do: title
  defp row_title(%ChangeSetRow{old_value: %{"title" => title}}), do: title
  defp row_title(%ChangeSetRow{}), do: "An item"
end
