defmodule Web.ActivityEquipmentLive do
  use Web, :live_view_app_layout

  import Web.Components.Scanner

  alias App.Model.ChangeSetRow
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Operation.ChangeActivityEquipment

  # Adding equipment to an activity (#271). Items come from the last activity of the same
  # kind, from a search, or from a phone's camera scanning barcodes, into a list with hours
  # to check. Sending the list writes them to D4H as equipment usages. Templates are
  # applied on their own page, ActivityTemplateLive (#162).
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    activity = Web.ActivityLive.fetch_activity(team, id)

    if activity.deleted_at do
      {:ok, Web.ActivityLive.leave_deleted(socket, activity)}
    else
      last = EquipmentUsage.last_activity_with_equipment(activity)

      socket =
        socket
        |> assign(page_title: "Add equipment", activity: activity, lines: [])
        |> assign(q: "", results: [], last: last)
        |> assign(scan_message: nil, scan_failed: false)
        |> assign(last_usages: if(last, do: EquipmentUsage.for_activity(last), else: []))
        |> load_usages()

      {:ok, socket}
    end
  end

  @doc """
  The hours an item from a search or a scan starts at: 2, South Fraser's most common. A fixed
  number, not the activity's length, as Andrew asked (2026-10-11). Templates set their own.
  """
  def default_minutes, do: 120

  defp load_usages(socket) do
    usages = EquipmentUsage.for_activity(socket.assigns.activity)
    used = MapSet.new(usages, & &1.equipment_item_id)
    assign(socket, usages: usages, used: used)
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
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
          <.button id="equipment-add-last" type="button" phx-click="add-last">
            Add {Service.Format.count(length(@last_usages), one: "%d item", many: "%d items")}
          </.button>
        </section>

        <section id="equipment-search" class="mb-8">
          <h2 class="heading">Find an item</h2>
          <div class="hidden pointer-coarse:block mb-4">
            <.qr_scanner
              id="equipment-scanner"
              label="Scan barcodes"
              reader={:barcode}
              data-continuous
            />
            <.scan_message message={@scan_message} scan_failed={@scan_failed} />
          </div>
          <.item_search q={@q} results={@results} />
        </section>

        <p class="hint">
          To add a template's items, tags, and groups in one step, <.a navigate={
            ~p"/teams/#{@current_team}/activities/#{@activity.id}/templates"
          }>apply a template</.a>.
        </p>
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
            <.lines_table :if={@lines != []} id="equipment-lines-table" lines={@lines} km />
            <.form_actions>
              <.button
                id="equipment-send"
                variant={:success}
                phx-disable-with="Adding…"
              >
                Add {count_items(length(@lines))}
              </.button>
            </.form_actions>
          </.form>
          <p :if={@lines == []} id="equipment-nothing-to-add" class="hint">
            Add items from the last {@activity.activity_kind}, a search, or a scan. Check the hours and a vehicle's km, then add them.
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
              <.a navigate={~p"/teams/#{@current_team}/equipment/#{usage.equipment_item.id}"}>{usage.equipment_item.title}</.a>
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
                data-confirm={"Remove #{usage.equipment_item.title} from this activity?"}
              >
                Remove
              </.button>
            </:col>
          </.table>
          <p :if={@usages == []} class="hint">No equipment on this activity yet.</p>
        </section>
      </main>
    </div>
    """
  end

  @doc "What a usage counted: hours for equipment, km for a vehicle, a count for a supply."
  def amount(%EquipmentUsage{minutes: minutes}) when is_integer(minutes) and minutes > 0,
    do: Service.Format.duration(minutes)

  def amount(%EquipmentUsage{distance: km}) when is_integer(km) and km > 0,
    do: Service.Format.km(km)

  def amount(%EquipmentUsage{used: used}) when is_integer(used) and used > 0,
    do: "#{Service.Format.number(used)} used"

  def amount(%EquipmentUsage{}), do: ""

  attr :id, :string, required: true
  attr :lines, :list, required: true
  attr :km, :boolean, default: false, doc: "whether a vehicle takes km"

  @doc """
  The items about to be added, each with an hours field when D4H counts hours for it,
  and with `km` a km field for a vehicle. Shared with the template form, which has no km since
  each trip differs. Inputs are named `hours[item id]` and `km[item id]`.
  """
  def lines_table(assigns) do
    ~H"""
    <.table id={@id} rows={@lines} row_id={&"line-#{&1.item.id}"} class="table-striped">
      <:col :let={line} label="Item">
        {line.item.title} <span :if={line.item.kind} class="hint">{line.item.kind}</span>
      </:col>
      <:col :let={line} label={if @km, do: "Used", else: "Hours"} class="w-px whitespace-nowrap">
        <span class="flex items-center gap-2">
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
          /> <span :if={@km and EquipmentItem.takes_hours?(line.item)} class="hint">hours</span>
          <input
            :if={@km and EquipmentItem.takes_km?(line.item)}
            type="number"
            id={"km-#{line.item.id}"}
            name={"km[#{line.item.id}]"}
            value={line.km}
            min="0"
            step="1"
            class="w-16"
            aria-label={"Km for #{line.item.title}"}
          /> <span :if={@km and EquipmentItem.takes_km?(line.item)} class="hint">km</span>
          <span
            :if={
              !EquipmentItem.takes_hours?(line.item) and
                !(@km and EquipmentItem.takes_km?(line.item))
            }
            class="hint"
          >
            {if EquipmentItem.takes_km?(line.item),
              do: "Not counted for vehicles",
              else: "Not counted"}
          </span>
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

  @doc "A search box for items, with an add button for each one found. Shared with the template form."
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
    <.table
      :if={@results != []}
      id="item-search-results"
      rows={@results}
      row_id={&"result-#{&1.id}"}
      class="table-striped"
    >
      <:col :let={item} label="Item">
        {item.title} <span :if={item.kind} class="hint">{item.kind}</span>
      </:col>
      <:col :let={item} label="" class="w-px whitespace-nowrap">
        <.button
          id={"item-add-#{item.id}"}
          type="button"
          size={:sm}
          phx-click="add-item"
          phx-value-id={item.id}
        >
          Add
        </.button>
      </:col>
    </.table>
    <p :if={@q != "" and @results == []} class="hint">No items match "{@q}".</p>
    """
  end

  attr :message, :any, required: true, doc: "{band kind, text}, or nil"
  attr :scan_failed, :boolean, required: true

  @doc "What the last scan did, under the scanner. Shared with the equipment page."
  def scan_message(assigns) do
    ~H"""
    <.band
      :if={@message}
      id="scan-message"
      role="status"
      kind={elem(@message, 0)}
      title={elem(@message, 1)}
      class="mt-4"
    />
    <p :if={@scan_failed} id="scan-failed" class="text-danger-text mt-2">
      The camera did not start. Allow camera access, or type the barcode in the search.
    </p>
    """
  end

  @doc "The answer to a scan that matches no item."
  def no_item_text(code), do: "No item has the barcode #{String.trim(code)}."

  @doc """
  What a scan of `item`, nil when no item has the barcode, does to the list: `:add`,
  `:already` when the item is listed or on the activity, or `:refused`. Each comes with
  the text to show. `used` holds the ids of the items on the activity.
  """
  def scan_result(nil, code, _lines, _used), do: {:refused, no_item_text(code)}

  def scan_result(%EquipmentItem{} = item, _code, lines, used) do
    cond do
      not EquipmentItem.in_service?(item) ->
        {:refused, "#{item.title} cannot be added. It is #{item.status}."}

      MapSet.member?(used, item.id) ->
        {:already, "#{item.title} is already on this activity."}

      Enum.any?(lines, &(&1.item.id == item.id)) ->
        {:already, "#{item.title} is already in the list to add."}

      true ->
        {:add, "Added #{item.title}."}
    end
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
        %{item: item, hours: Service.Convert.minutes_to_hours(minutes), km: ""}
      end)

    lines ++ added
  end

  @doc """
  `lines` with what was typed in `params`: `hours` and `km`, each a map of item id (as
  text) to the number typed.
  """
  def put_typed(lines, params) do
    hours = params["hours"] || %{}
    km = params["km"] || %{}

    Enum.map(lines, fn line ->
      id = Integer.to_string(line.item.id)
      %{line | hours: Map.get(hours, id, line.hours), km: Map.get(km, id, line.km)}
    end)
  end

  @doc "A line as ChangeActivityEquipment.add/6 takes it. Shared with ActivityTemplateLive."
  def to_add(line),
    do: %{
      item: line.item,
      minutes: Service.Convert.hours_to_minutes(line.hours),
      km: parse_km(line.km)
    }

  @doc "Whole km from the text typed, or nil when it is blank or not a number."
  def parse_km(text) do
    case text |> to_string() |> String.trim() |> Integer.parse() do
      {km, ""} when km >= 0 -> km
      _other -> nil
    end
  end

  def remove_line(lines, id), do: Enum.reject(lines, &(Integer.to_string(&1.item.id) == id))

  @doc "Items found for `q`, without the ones whose ids are in `skip`."
  def search(team, q, skip),
    do: team.id |> EquipmentItem.search(q) |> Enum.reject(&MapSet.member?(skip, &1.id))

  def handle_event("add-last", _params, socket) do
    new =
      for usage <- socket.assigns.last_usages, EquipmentItem.in_service?(usage.equipment_item) do
        {usage.equipment_item, usage.minutes || default_minutes()}
      end

    {:noreply, add(socket, new)}
  end

  def handle_event("add-item", %{"id" => id}, socket) do
    item = EquipmentItem.find!(socket.assigns.current_team, id)
    {:noreply, add(socket, [{item, default_minutes()}])}
  end

  def handle_event("scanned", %{"code" => code}, socket) do
    item = EquipmentItem.find_by_code(socket.assigns.current_team.id, code)

    socket =
      case scan_result(item, code, socket.assigns.lines, socket.assigns.used) do
        {:add, text} ->
          socket |> add([{item, default_minutes()}]) |> scanned(:success, text)

        {:already, text} ->
          scanned(socket, :warning, text)

        {:refused, text} ->
          scanned(socket, :danger, text)
      end

    {:noreply, socket}
  end

  def handle_event("scan_failed", _params, socket),
    do: {:noreply, assign(socket, scan_failed: true)}

  def handle_event("remove-line", %{"id" => id}, socket),
    do: {:noreply, assign(socket, lines: remove_line(socket.assigns.lines, id))}

  def handle_event("search", %{"q" => q}, socket) do
    skip = MapSet.union(socket.assigns.used, MapSet.new(socket.assigns.lines, & &1.item.id))
    results = search(socket.assigns.current_team, q, skip)
    {:noreply, assign(socket, q: q, results: results)}
  end

  def handle_event("hours", params, socket),
    do: {:noreply, assign(socket, lines: put_typed(socket.assigns.lines, params))}

  def handle_event("send", params, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns
    lines = socket.assigns.lines |> put_typed(params) |> Enum.map(&to_add/1)

    case ChangeActivityEquipment.add(team, activity, lines, [], user, DateTime.utc_now()) do
      {:ok, rows} ->
        socket =
          socket
          |> put_flash(flash_kind(rows), result_text(rows, "added"))
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
             |> put_flash(
               flash_kind(rows),
               result_text(rows, "removed")
             )
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

  defp scanned(socket, kind, text) do
    socket
    |> assign(scan_message: {kind, text})
    |> push_event("scan-sound", %{sound: if(kind == :success, do: :ok, else: :error)})
  end

  @doc "The flash kind for written rows: :info when all applied, else :error."
  def flash_kind(rows),
    do: if(Enum.all?(rows, &(&1.status == :applied)), do: :info, else: :error)

  @doc """
  What happened, as one message: "3 items added.", "2 tags added." when a template's tags
  went, and then each row that didn't go, with why. Shared with ActivityTemplateLive.
  """
  def result_text(rows, verb) do
    {tag_rows, item_rows} = Enum.split_with(rows, &(&1.action == :set_activity_tags))
    applied = Enum.count(item_rows, &(&1.status == :applied))

    items =
      if item_rows != [] or tag_rows == [], do: ["#{count_items(applied)} #{verb}."], else: []

    tags = for %{status: :applied} = row <- tag_rows, do: tags_added(row)

    rows
    |> Enum.reject(&(&1.status == :applied))
    |> Enum.map(&"#{row_title(&1)}: #{&1.error}")
    |> then(&Enum.join(items ++ tags ++ &1, " "))
  end

  defp tags_added(row), do: "#{row.new_value["titles"] |> length() |> count_tags()} added."

  defp count_items(n), do: Service.Format.count(n, one: "%d item", many: "%d items")
  defp count_tags(n), do: Service.Format.count(n, one: "%d tag", many: "%d tags")

  defp row_title(%ChangeSetRow{action: :set_activity_tags}), do: "Tags"
  defp row_title(%ChangeSetRow{new_value: %{"title" => title}}), do: title
  defp row_title(%ChangeSetRow{old_value: %{"title" => title}}), do: title
  defp row_title(%ChangeSetRow{}), do: "An item"
end
