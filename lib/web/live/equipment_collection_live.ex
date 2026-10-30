defmodule Web.EquipmentCollectionLive do
  use Web, :live_view_app_layout

  import Web.ActivityEquipmentLive, only: [scan_message: 1, no_item_text: 1]
  import Web.Components.Equipment
  import Web.Components.FilterBar
  import Web.Components.Scanner
  import Web.Components.StatSwitch

  alias App.Adapter.D4H
  alias App.Model.EquipmentItem
  alias App.Model.Member
  alias App.Model.Standing
  alias App.Model.Team
  alias App.ViewData.EquipmentList

  # The team's equipment, copied from D4H or SAR Duty Records (#271). It opens on the
  # places and categories, with counts; picking one, searching, or another filter lists
  # items, grouped by where they are. A Records team adds items here. On a phone,
  # scanning a barcode opens its item. Where takes a member too, `?place=member-<id>`
  # (#490), or retiring members, `?place=retiring` (#514), and opens on All, as the
  # member's sidebar and Equipment tab count.
  def mount(_params, _session, socket) do
    rows = socket.assigns.current_team.id |> EquipmentItem.get_all() |> EquipmentList.rows()
    in_service = EquipmentList.filter(rows, "in-service", "", DateTime.utc_now())

    socket =
      assign(socket,
        page_title: "Equipment",
        rows: rows,
        places: EquipmentList.places(in_service),
        categories: EquipmentList.categories(in_service),
        place_options:
          EquipmentList.place_options(rows, Team.retiring?(socket.assigns.current_team)),
        category_options: [
          {"All", ""} | rows |> EquipmentList.categories() |> Enum.map(&elem(&1, 0))
        ],
        scan_message: nil,
        scan_failed: false
      )

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    q = String.trim(params["q"] || "")
    place = params["place"] || ""
    category = params["category"] || ""
    now = DateTime.utc_now()

    # A held place opens on All: retired items are still with the member (#490).
    default_show = if EquipmentList.held_place?(place), do: "all", else: "in-service"

    show =
      if params["show"] in EquipmentList.show_values(), do: params["show"], else: default_show

    held = held_in(socket.assigns.current_team, place, now)
    narrowed = EquipmentList.narrow(socket.assigns.rows, place, category, held)
    rows = EquipmentList.filter(narrowed, show, q, now)

    socket =
      assign(socket,
        show: show,
        default_show: default_show,
        show_counts: show_counts(narrowed, now),
        q: q,
        browsing: EquipmentList.browsing?(show, q, place, category),
        count: length(rows),
        held_place?: EquipmentList.held_place?(place),
        by_holder?: EquipmentList.by_holder?(place),
        groups: groups(rows, place, held),
        form:
          to_form(
            # The default stays out of the URL, so a new place opens on its own default.
            %{
              "q" => q,
              "place" => place,
              "category" => category,
              "show" => if(show == default_show, do: "", else: show)
            },
            as: "form"
          )
      )

    {:noreply, socket}
  end

  def handle_event("change", %{"form" => form}, socket) do
    params =
      form |> Map.take(["q", "place", "category", "show"]) |> Map.reject(&(elem(&1, 1) == ""))

    {:noreply,
     push_patch(socket, to: filter_path(socket.assigns.current_team, params), replace: true)}
  end

  # A scan opens the item, even a retired one: this page finds items, it does not add them.
  def handle_event("scanned", %{"code" => code}, socket) do
    team = socket.assigns.current_team

    case EquipmentItem.find_by_code(team.id, code) do
      nil ->
        {:noreply,
         socket
         |> assign(scan_message: {:danger, no_item_text(code)})
         |> push_event("scan-sound", %{sound: :error})}

      item ->
        {:noreply, push_navigate(socket, to: ~p"/teams/#{team}/equipment/#{item.id}")}
    end
  end

  def handle_event("scan_failed", _params, socket),
    do: {:noreply, assign(socket, scan_failed: true)}

  # Each stat switch tile's count, in the place and category picked.
  defp show_counts(narrowed, now) do
    Map.new(EquipmentList.show_values(), fn value ->
      {value, length(EquipmentList.filter(narrowed, value, "", now))}
    end)
  end

  # What a held place lists, keyed by item id: what retiring members hold, or what a
  # member holds, looked up through the team, to their name. None for any other place,
  # or another team's member.
  defp held_in(team, "retiring", now),
    do: EquipmentItem.holders(team, Standing.retiring_member_ids_query(team, now))

  defp held_in(team, place, _now) do
    holder = EquipmentList.member_id(place) && Member.find(team, EquipmentList.member_id(place))

    if holder,
      do: team |> EquipmentItem.held_by(holder) |> Map.new(&{&1.id, holder.name}),
      else: %{}
  end

  # Several members' items group by member, in one table; one member's under their name;
  # anything else by place.
  defp groups(rows, place, held) do
    cond do
      EquipmentList.by_holder?(place) -> EquipmentList.group_by_holder(rows)
      EquipmentList.held_place?(place) -> EquipmentList.group_held(rows, held)
      true -> EquipmentList.group(rows)
    end
  end

  defp filter_path(team, params), do: ~p"/teams/#{team}/equipment?#{params}"

  # The page's path with some filters changed, for the filter bar's chips.
  defp path_fn(team, form) do
    fn changes ->
      params =
        form.params
        |> Map.merge(Map.new(changes, fn {key, value} -> {Atom.to_string(key), value} end))
        |> Map.reject(&(elem(&1, 1) == ""))

      filter_path(team, params)
    end
  end

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">{@page_title}</h1>
      <:action>
        <.button
          :if={D4H.records?(@current_team)}
          id="equipment-add"
          variant={:success}
          navigate={~p"/teams/#{@current_team}/equipment/new"}
        >
          Add item
        </.button>
      </:action>
    </.heading_row>

    <.stat_switch :if={@rows != []} id="equipment-switch" label="Show">
      <:view
        :for={{label, value} <- EquipmentList.shows()}
        id={"equipment-view-#{value}"}
        patch={path_fn(@current_team, @form).(show: if(value == @default_show, do: "", else: value))}
        current={@show == value}
        count={@show_counts[value]}
      >
        {label}
      </:view>
    </.stat_switch>

    <.filter_bar
      for={@form}
      id="equipment-filter"
      count={Service.Format.count(@count, one: "%d item", many: "%d items")}
      repeats={@count == @show_counts[@show]}
      clear={filter_path(@current_team, %{})}
      path_fn={path_fn(@current_team, @form)}
      hidden={[@form[:show]]}
    >
      <:search field={@form[:q]} placeholder="Name, barcode, or serial" />
      <:filter
        field={@form[:place]}
        label="Where"
        type="combobox"
        options={@place_options}
        default=""
      />
      <:filter field={@form[:category]} label="Category" options={@category_options} default="" />
    </.filter_bar>

    <div :if={@rows != []} class="hidden pointer-coarse:block measure mb-6">
      <.qr_scanner id="equipment-scanner" label="Scan a barcode" reader={:barcode} />
      <.scan_message message={@scan_message} scan_failed={@scan_failed} />
    </div>

    <div
      :if={@browsing and @rows != []}
      id="equipment-browse"
      class="grid items-start gap-8 md:grid-cols-2"
    >
      <.count_table
        id="equipment-places"
        label="Where"
        counts={@places}
        path={&filter_path(@current_team, place: &1)}
      />
      <.count_table
        id="equipment-categories"
        label="Category"
        counts={@categories}
        path={&filter_path(@current_team, category: &1)}
      />
    </div>

    <%!-- Several members' items: one table, so the columns line up, a title row each. --%>
    <.table
      :if={!@browsing and @by_holder? and @groups != []}
      id="equipment-holders"
      groups={
        for {id, name, rows} <- @groups,
            do: %{id: "member-#{id}", title: "#{name} · #{length(rows)}", rows: rows}
      }
      row_id={&"item-#{&1.item.id}"}
      class="table-striped"
    >
      <:col :let={row} label="Item">
        <.item_cell item={row.item} team={@current_team} />
      </:col>
      <:col :let={row} label="Where">{row.inside}</:col>
      <:col :let={row} label="Category">{row.item.kind}</:col>
      <:col :let={row} label="Barcode" class="w-px whitespace-nowrap">{row.item.barcode}</:col>
      <:col :let={row} label="Expires" class="w-px whitespace-nowrap">
        <.expires_cell value={row.item.expires_at} timezone={@current_team.timezone} />
      </:col>
    </.table>

    <section
      :for={{place, rows} <- if(@browsing or @by_holder?, do: [], else: @groups)}
      id={"place-#{slug(place)}"}
      class="mb-8"
    >
      <h2 class="heading">{place} · {length(rows)}</h2>
      <%!-- A member's items, as their Equipment tab shows them. --%>
      <.held_table
        :if={@held_place?}
        id={"equipment-#{slug(place)}"}
        rows={rows}
        team={@current_team}
      />
      <.table
        :if={!@held_place?}
        id={"equipment-#{slug(place)}"}
        rows={rows}
        row_id={&"item-#{&1.item.id}"}
        class="table-striped"
      >
        <:col :let={row} label="Item">
          <.item_cell item={row.item} team={@current_team} />
        </:col>
        <:col :let={row} label="Where">
          {where(row)}
        </:col>
        <:col :let={row} label="Category">{row.item.kind}</:col>
        <:col :let={row} label="Barcode" class="w-px whitespace-nowrap">{row.item.barcode}</:col>
        <:col :let={row} label="Expires" class="w-px whitespace-nowrap">
          <.expires_cell value={row.item.expires_at} timezone={@current_team.timezone} />
        </:col>
      </.table>
    </section>

    <.empty_state :if={@rows == []} id="no-equipment" title="No equipment yet">
      {if D4H.records?(@current_team),
        do: "Add the team's first item.",
        else: "Equipment comes in with each refresh."}
    </.empty_state>
    <.empty_state
      :if={!@browsing and @rows != [] and @groups == []}
      id="no-matching-equipment"
      title="No items match"
    >
      Change the search or the filters.
    </.empty_state>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :counts, :list, required: true, doc: "{name, count}"
  attr :path, :any, required: true, doc: "the link for a name"

  defp count_table(assigns) do
    ~H"""
    <.table id={@id} rows={@counts} row_id={&"#{@id}-#{slug(elem(&1, 0))}"} class="table-striped">
      <:col :let={{name, _count}} label={@label}>
        <.a patch={@path.(name)}>{name}</.a>
      </:col>
      <:col :let={{_name, count}} label="Items" align="right" class="w-px whitespace-nowrap">
        {count}
      </:col>
    </.table>
    """
  end

  defp where(%{holder: nil, inside: inside}), do: inside
  defp where(%{holder: holder, inside: ""}), do: holder
  defp where(%{holder: holder, inside: inside}), do: "#{holder} › #{inside}"

  defp slug(place), do: place |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
end
