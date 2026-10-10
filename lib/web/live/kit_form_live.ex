defmodule Web.KitFormLive do
  use Web, :live_view_app_layout

  import Web.ActivityEquipmentLive, only: [lines_table: 1, item_search: 1]

  alias App.Model.EquipmentItem
  alias App.Model.Kit
  alias App.Operation.SaveKit
  alias Web.ActivityEquipmentLive

  # Adding and changing a kit: its name, and its items with their usual hours (#271).
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    Web.EquipmentItemLive.require_equipment!(team)
    kit = if id = params["id"], do: Kit.find!(team, id)

    lines =
      if kit,
        do:
          kit.kit_items
          |> Enum.sort_by(&String.downcase(&1.equipment_item.title))
          |> Enum.map(&{&1.equipment_item, &1.minutes})
          |> then(&ActivityEquipmentLive.add_lines([], &1)),
        else: []

    socket =
      socket
      |> assign(kit: kit, lines: lines, q: "", results: [])
      |> assign(page_title: if(kit, do: kit.title, else: "Add kit"))
      |> assign_form(Kit.build_changeset(kit || %Kit{}, %{}))

    {:ok, socket}
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "kit"))

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Equipment" path={~p"/teams/#{@current_team}/equipment"} />
      <:item label="Kits" path={~p"/teams/#{@current_team}/equipment/kits"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <section id="kit-search">
          <h2 class="heading">Find an item</h2>
          <.item_search q={@q} results={@results} />
        </section>
      </aside>
      <main class="content-2/3">
        <.form for={@form} id="kit-form" phx-change="validate" phx-submit="save">
          <.error_summary form={@form} />
          <.input field={@form[:title]} label="Name">Such as "Truck 1" or "Night search".</.input>

          <h2 class="heading">Items · {length(@lines)}</h2>
          <p class="hint mb-4">
            The hours are what each item adds to an activity. You can change them when you add the kit.
          </p>
          <.lines_table :if={@lines != []} id="kit-lines" lines={@lines} />
          <p :if={@lines == []} id="kit-no-items" class="hint mb-4">
            Find items to add on the right.
          </p>

          <.form_actions>
            <.button id="kit-save" variant={:success}>{if @kit, do: "Save kit", else: "Add kit"}</.button>
          </.form_actions>
        </.form>

        <section :if={@kit} id="kit-delete" class="mt-8">
          <h2 class="heading">Delete the kit</h2>
          <p>Its items stay in D4H, and on the activities they went on.</p>
          <.button
            id="kit-delete-button"
            type="button"
            variant={:danger}
            phx-click="delete"
            data-confirm={"Delete the #{@kit.title} kit?"}
          >
            Delete kit
          </.button>
        </section>
      </main>
    </div>
    """
  end

  def handle_event("validate", params, socket) do
    changeset =
      (socket.assigns.kit || %Kit{})
      |> Kit.build_changeset(params["kit"] || %{})
      |> Map.put(:action, :validate)

    lines = ActivityEquipmentLive.put_hours(socket.assigns.lines, params["hours"] || %{})
    {:noreply, socket |> assign(lines: lines) |> assign_form(changeset)}
  end

  def handle_event("save", params, socket) do
    team = socket.assigns.current_team
    lines = ActivityEquipmentLive.put_hours(socket.assigns.lines, params["hours"] || %{})

    kit_lines =
      Enum.map(lines, fn line ->
        minutes =
          if EquipmentItem.takes_hours?(line.item),
            do: Service.Convert.hours_to_minutes(line.hours),
            else: 0

        %{equipment_item_id: line.item.id, minutes: minutes}
      end)

    case SaveKit.save(team, socket.assigns.kit, params["kit"] || %{}, kit_lines) do
      {:ok, kit} ->
        socket =
          socket
          |> put_flash(:info, "Saved the #{kit.title} kit.")
          |> push_navigate(to: ~p"/teams/#{team}/equipment/kits")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, socket |> assign(lines: lines) |> assign_form(changeset)}
    end
  end

  def handle_event("delete", _params, socket) do
    %{current_team: team, kit: kit} = socket.assigns
    :ok = SaveKit.delete(team, kit)

    socket =
      socket
      |> put_flash(:info, "Deleted the #{kit.title} kit.")
      |> push_navigate(to: ~p"/teams/#{team}/equipment/kits")

    {:noreply, socket}
  end

  def handle_event("search", %{"q" => q}, socket) do
    skip = MapSet.new(socket.assigns.lines, & &1.item.id)
    results = ActivityEquipmentLive.search(socket.assigns.current_team, q, skip)
    {:noreply, assign(socket, q: q, results: results)}
  end

  def handle_event("add-item", %{"id" => id}, socket) do
    item = EquipmentItem.find!(socket.assigns.current_team, id)
    minutes = if EquipmentItem.takes_hours?(item), do: 60, else: 0
    lines = ActivityEquipmentLive.add_lines(socket.assigns.lines, [{item, minutes}])
    results = Enum.reject(socket.assigns.results, &(&1.id == item.id))
    {:noreply, assign(socket, lines: lines, results: results)}
  end

  def handle_event("remove-line", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, lines: ActivityEquipmentLive.remove_line(socket.assigns.lines, id))}
end
