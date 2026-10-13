defmodule Web.EquipmentCollectionLive do
  use Web, :live_view_app_layout

  import Web.ActivityEquipmentLive, only: [scan_message: 1, no_item_text: 1]
  import Web.Components.Scanner

  alias App.Adapter.D4H
  alias App.Model.EquipmentItem
  alias App.ViewData.EquipmentList

  # The team's equipment, copied from D4H or SAR Duty Records (#271). It opens on the
  # places and categories, with counts; picking one, searching, or another filter lists
  # items, grouped by where they are. A Records team adds items here. On a phone,
  # scanning a barcode opens its item.
  def mount(_params, _session, socket) do
    rows = socket.assigns.current_team.id |> EquipmentItem.get_all() |> EquipmentList.rows()
    in_service = EquipmentList.filter(rows, "in-service", "", DateTime.utc_now())

    socket =
      assign(socket,
        page_title: "Equipment",
        rows: rows,
        places: EquipmentList.places(in_service),
        categories: EquipmentList.categories(in_service),
        place_options: options("Any place", EquipmentList.places(rows)),
        category_options: options("Any category", EquipmentList.categories(rows)),
        scan_message: nil,
        scan_failed: false
      )

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    show =
      if params["show"] in EquipmentList.show_values(), do: params["show"], else: "in-service"

    q = String.trim(params["q"] || "")
    place = params["place"] || ""
    category = params["category"] || ""
    now = DateTime.utc_now()

    rows =
      socket.assigns.rows
      |> EquipmentList.filter(show, q, now)
      |> EquipmentList.narrow(place, category)

    socket =
      assign(socket,
        show: show,
        q: q,
        browsing: EquipmentList.browsing?(show, q, place, category),
        count: length(rows),
        groups: EquipmentList.group(rows),
        form:
          to_form(%{"q" => q, "place" => place, "category" => category, "show" => show},
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

  defp filter_path(team, params), do: ~p"/teams/#{team}/equipment?#{params}"

  defp options(any, counts), do: [{any, ""} | Enum.map(counts, &elem(&1, 0))]

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team} />
    <div class="heading-row">
      <h1 class="title">{@page_title}</h1>
      <div class="flex gap-2">
        <.button
          :if={D4H.records?(@current_team)}
          id="equipment-add"
          variant={:success}
          navigate={~p"/teams/#{@current_team}/equipment/new"}
        >
          Add item
        </.button>
      </div>
    </div>

    <.form
      for={@form}
      id="equipment-filter"
      phx-change="change"
      phx-submit="change"
      class="filter-form"
    >
      <.input field={@form[:q]} label="Search" placeholder="Name, barcode, or serial" />
      <.input field={@form[:place]} label="Place" type="select" options={@place_options} />
      <.input field={@form[:category]} label="Category" type="select" options={@category_options} />
      <.input field={@form[:show]} label="Show" type="select" options={EquipmentList.shows()} />
    </.form>

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
        label="Place"
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

    <div :if={!@browsing} class="table-summary">
      <span class="table-summary-count">
        {Service.Format.count(@count, one: "%d item", many: "%d items")}
      </span>
    </div>

    <section
      :for={{place, rows} <- if(@browsing, do: [], else: @groups)}
      id={"place-#{slug(place)}"}
      class="mb-8"
    >
      <h2 class="heading">{place} · {length(rows)}</h2>
      <.table
        id={"equipment-#{slug(place)}"}
        rows={rows}
        row_id={&"item-#{&1.item.id}"}
        class="table-striped"
      >
        <:col :let={row} label="Item">
          <.a navigate={~p"/teams/#{@current_team}/equipment/#{row.item.id}"}>{row.item.title}</.a>
          <.status_badge item={row.item} />
        </:col>
        <:col :let={row} label="Where">
          {where(row)}
        </:col>
        <:col :let={row} label="Category">{row.item.kind}</:col>
        <:col :let={row} label="Barcode" class="w-px whitespace-nowrap">{row.item.barcode}</:col>
        <:col :let={row} label="Expires" align="right" class="w-px whitespace-nowrap">
          <span :if={row.item.expires_at}>
            {Service.Format.date_short(row.item.expires_at, @current_team.timezone)}
          </span>
        </:col>
      </.table>
    </section>

    <.empty_state :if={@rows == []} id="no-equipment" title="No equipment yet">
      {if D4H.records?(@current_team),
        do: "Add the team's first item.",
        else: "SAR Duty copies equipment from D4H when it refreshes."}
    </.empty_state>
    <.empty_state
      :if={!@browsing and @rows != [] and @groups == []}
      id="no-matching-equipment"
      title="No items match"
    >
      Change the search or what to show.
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

  attr :item, EquipmentItem, required: true

  def status_badge(%{item: %{status: "operational"}} = assigns), do: ~H""

  def status_badge(%{item: %{status: status}} = assigns)
      when status in ["unserviceable", "lost"] do
    ~H"""
    <.badge kind={:danger}>{String.capitalize(@item.status)}</.badge>
    """
  end

  def status_badge(assigns) do
    ~H"""
    <.badge>{String.capitalize(@item.status)}</.badge>
    """
  end
end
