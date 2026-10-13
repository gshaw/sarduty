defmodule Web.ActivityEquipmentLive do
  use Web, :live_view_app_layout

  import Web.Components.Scanner

  alias App.Adapter.D4H
  alias App.Model.ChangeSetRow
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.Kit
  alias App.Operation.ChangeActivityEquipment
  alias App.Operation.InviteGroups

  # Adding equipment to an activity (#271). Items come from the last activity of the same
  # kind, from kits, from a search, or from a phone's camera scanning barcodes, into a list
  # with hours to check. A kit's tags and groups join the list too (#162). Sending the
  # list writes them to D4H as equipment usages, the activity's tags, and invites.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    activity = Web.ActivityLive.fetch_activity(team, id)

    if activity.deleted_at do
      {:ok, Web.ActivityLive.leave_deleted(socket, activity)}
    else
      last = EquipmentUsage.last_activity_with_equipment(activity)

      socket =
        socket
        |> assign(
          page_title: "Add equipment",
          activity: activity,
          lines: [],
          tags: [],
          groups: []
        )
        |> assign(q: "", results: [])
        |> assign(kits: Kit.get_all(team.id), last: last, service: D4H.service_name(team))
        |> assign(scan_message: nil, scan_failed: false)
        |> assign(last_usages: if(last, do: EquipmentUsage.for_activity(last), else: []))
        |> load_usages()

      {:ok, socket}
    end
  end

  @doc """
  The hours an item from a search or a scan starts at: 2, South Fraser's most common. A fixed
  number, not the activity's length, as Andrew asked (2026-10-11). Kits set their own.
  """
  def default_minutes, do: 120

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
              <span class="hint">{kit_contents(kit)}</span>
            </li>
          </ul>
          <p class="hint">
            <.a navigate={~p"/teams/#{@current_team}/equipment/kits"}>
              {if @kits == [], do: "Add a kit", else: "Change kits"}
            </.a>
            for gear, tags, and groups that go together.
          </p>
        </section>

        <section id="equipment-search">
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
      </aside>

      <main class="content-2/3">
        <section id="equipment-to-add" class="mb-8">
          <h2 class="heading">To add</h2>
          <.form
            :if={@lines != [] or @tags != [] or @groups != []}
            for={%{}}
            id="equipment-lines"
            phx-change="hours"
            phx-submit="send"
          >
            <.lines_table :if={@lines != []} id="equipment-lines-table" lines={@lines} km />
            <div :if={@tags != []} id="equipment-tags" class="mt-4">
              <h3 class="subheading">Tags</h3>
              <p class="hint mb-2">The activity keeps the tags it has.</p>
              <.tags_to_add id="equipment-tags-list" tags={@tags} />
            </div>
            <div :if={@groups != []} id="equipment-groups" class="mt-4">
              <h3 class="subheading">Invite</h3>
              <p class="hint mb-2">
                SAR Duty invites each member of these groups who isn't on the activity. They answer in {@service}.
              </p>
              <.groups_to_invite id="equipment-groups-list" groups={@groups} />
            </div>
            <.form_actions>
              <.button
                id="equipment-send"
                variant={:success}
                phx-disable-with="Adding…"
              >
                {to_add_text(length(@lines), length(@tags), length(@groups))}
              </.button>
            </.form_actions>
          </.form>
          <p
            :if={@lines == [] and @tags == [] and @groups == []}
            id="equipment-nothing-to-add"
            class="hint"
          >
            Add items from the last {@activity.activity_kind}, a kit, a search, or a scan. Check the hours and a vehicle's km, then add them.
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

  def amount(%EquipmentUsage{distance: km}) when is_integer(km) and km > 0, do: "#{km} km"
  def amount(%EquipmentUsage{used: used}) when is_integer(used) and used > 0, do: "#{used} used"
  def amount(%EquipmentUsage{}), do: ""

  attr :id, :string, required: true
  attr :lines, :list, required: true
  attr :km, :boolean, default: false, doc: "whether a vehicle takes km"

  @doc """
  The items about to be added, each with an hours field when D4H counts hours for it,
  and with `km` a km field for a vehicle. Shared with the kit form, which has no km since
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

  attr :id, :string, required: true
  attr :tags, :list, required: true

  @doc "Tags about to be added, each with a remove button. Shared with the kit form."
  def tags_to_add(assigns) do
    ~H"""
    <ul id={@id} class="action-list mb-4">
      <li :for={tag <- @tags} id={"tag-#{tag.id}"}>
        <.button
          id={"tag-remove-#{tag.id}"}
          type="button"
          size={:sm}
          variant={:secondary}
          phx-click="remove-tag"
          phx-value-id={tag.id}
        >
          Remove
        </.button>
        <.badge kind={:outline}>{tag.title}</.badge>
      </li>
    </ul>
    """
  end

  attr :id, :string, required: true
  attr :groups, :list, required: true

  @doc "Groups about to be invited, each with a remove button. Shared with the kit form."
  def groups_to_invite(assigns) do
    ~H"""
    <ul id={@id} class="action-list mb-4">
      <li :for={group <- @groups} id={"group-#{group.id}"}>
        <.button
          id={"group-remove-#{group.id}"}
          type="button"
          size={:sm}
          variant={:secondary}
          phx-click="remove-group"
          phx-value-id={group.id}
        >
          Remove
        </.button>
        {group.title}
      </li>
    </ul>
    """
  end

  @doc ~s(What a kit holds, as "3 items, 2 tags, 1 group".)
  def kit_contents(kit) do
    tags = length(kit.kit_tags)
    groups = length(kit.kit_groups)

    [count_items(length(kit.kit_items))]
    |> Kernel.++(if tags > 0, do: [count_tags(tags)], else: [])
    |> Kernel.++(if groups > 0, do: [count_groups(groups)], else: [])
    |> Enum.join(", ")
  end

  @doc """
  What the send button does: "Add 3 items", "Add 3 items and 2 tags", "Invite 1 group",
  or "Add 3 items and invite 1 group".
  """
  def to_add_text(lines, tags, groups \\ 0) do
    adds =
      case {lines, tags} do
        {0, 0} -> nil
        {_lines, 0} -> count_items(lines)
        {0, _tags} -> count_tags(tags)
        _both -> "#{count_items(lines)} and #{count_tags(tags)}"
      end

    case {adds, groups} do
      {adds, 0} -> "Add #{adds}"
      {nil, groups} -> "Invite #{count_groups(groups)}"
      {adds, groups} -> "Add #{adds} and invite #{count_groups(groups)}"
    end
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

  defp to_add(line),
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

  @doc """
  `tags` with a kit's `new` tags added, A to Z, leaving out any the activity has by title
  (`titles`). The send reads D4H again, so a stale title only means a tag goes unlisted.
  """
  def add_tags(tags, new, titles) do
    titles = titles || []

    (tags ++ Enum.reject(new, &(&1.title in titles)))
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&String.downcase(&1.title))
  end

  @doc "`groups` with a kit's `new` groups added, each once, A to Z."
  def add_groups(groups, new),
    do: (groups ++ new) |> Enum.uniq_by(& &1.id) |> Enum.sort_by(&String.downcase(&1.title))

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

  def handle_event("add-kit", %{"id" => id}, socket) do
    kit = Kit.find!(socket.assigns.current_team, id)

    new =
      for line <- kit.kit_items, EquipmentItem.in_service?(line.equipment_item) do
        {line.equipment_item, line.minutes}
      end

    tags = add_tags(socket.assigns.tags, Kit.tags(kit), socket.assigns.activity.tags)
    groups = add_groups(socket.assigns.groups, Kit.groups(kit))
    {:noreply, socket |> add(new) |> assign(tags: tags, groups: groups)}
  end

  def handle_event("remove-group", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket,
         groups: Enum.reject(socket.assigns.groups, &(Integer.to_string(&1.id) == id))
       )}

  def handle_event("remove-tag", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, tags: Enum.reject(socket.assigns.tags, &(Integer.to_string(&1.id) == id)))}

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
    now = DateTime.utc_now()

    # Equipment and tags go first; a refusal there leaves the invites unsent too.
    case add_equipment(team, activity, lines, socket.assigns.tags, user, now) do
      {:ok, rows} ->
        {kind, text} = invite(team, activity, socket.assigns.groups, user, now, rows)

        socket =
          socket
          |> put_flash(kind, text)
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

  defp add_equipment(_team, _activity, [], [], _user, _now), do: {:ok, []}

  defp add_equipment(team, activity, lines, tags, user, now),
    do: ChangeActivityEquipment.add(team, activity, lines, tags, user, now)

  # The flash for the equipment `rows` and the invites, as {kind, text}.
  defp invite(_team, _activity, [], _user, _now, rows),
    do: {flash_kind(rows), result_text(rows, "added")}

  defp invite(team, activity, groups, user, now, rows) do
    {kind, text} =
      case InviteGroups.call(team, activity, groups, user, now) do
        {:ok, invites} -> {flash_kind(rows ++ invites), invite_text(invites)}
        {:error, text} -> {:error, text}
      end

    if rows == [], do: {kind, text}, else: {kind, "#{result_text(rows, "added")} #{text}"}
  end

  @doc """
  What the invites did: "8 members invited.", then how many didn't go and why. No rows
  means everyone was on the activity already.
  """
  def invite_text([]), do: "Everyone in those groups is on the activity already."

  def invite_text(rows) do
    {applied, other} = Enum.split_with(rows, &(&1.status == :applied))

    not_invited =
      other
      |> Enum.group_by(& &1.error)
      |> Enum.map(fn {error, rows} -> "#{count_members(length(rows))} not invited: #{error}" end)

    Enum.join(["#{count_members(length(applied))} invited." | not_invited], " ")
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

  defp flash_kind(rows),
    do: if(Enum.all?(rows, &(&1.status == :applied)), do: :info, else: :error)

  @doc """
  What happened, as one message: "3 items added.", "2 tags added." when a kit's tags
  went, and then each row that didn't go, with why.
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
  defp count_groups(n), do: Service.Format.count(n, one: "%d group", many: "%d groups")
  defp count_members(n), do: Service.Format.count(n, one: "%d member", many: "%d members")

  defp row_title(%ChangeSetRow{action: :set_activity_tags}), do: "Tags"
  defp row_title(%ChangeSetRow{new_value: %{"title" => title}}), do: title
  defp row_title(%ChangeSetRow{old_value: %{"title" => title}}), do: title
  defp row_title(%ChangeSetRow{}), do: "An item"
end
