defmodule Web.KitFormLive do
  use Web, :live_view_app_layout

  import Web.ActivityEquipmentLive, only: [lines_table: 1, item_search: 1, tags_to_add: 1]

  alias App.Model.EquipmentItem
  alias App.Model.Kit
  alias App.Model.Tag
  alias App.Operation.SaveKit
  alias Web.ActivityEquipmentLive

  # Adding and changing a kit: its name, its items with their usual hours (#271), and its
  # tags (#162). Tags come from the sync's copy of the team's D4H tags.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
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
      |> assign(tags: if(kit, do: Kit.tags(kit), else: []), all_tags: Tag.get_all(team.id))
      |> assign(tag_q: "")
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
        <section id="kit-search" class="mb-8">
          <h2 class="heading">Find an item</h2>
          <.item_search q={@q} results={@results} />
        </section>

        <section id="kit-tag-search">
          <h2 class="heading">Find a tag</h2>
          <.tag_search q={@tag_q} tags={tag_results(@all_tags, @tags, @tag_q)} />
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

          <h2 class="heading mt-8">Tags · {length(@tags)}</h2>
          <p class="hint mb-4">
            Adding the kit adds these tags to the activity and keeps the tags it has.
          </p>
          <.tags_to_add :if={@tags != []} id="kit-tags" tags={@tags} />
          <p :if={@tags == []} id="kit-no-tags" class="hint mb-4">
            Find tags to add on the right.
          </p>

          <.form_actions>
            <.button id="kit-save" variant={:success}>{if @kit, do: "Save kit", else: "Add kit"}</.button>
          </.form_actions>
        </.form>

        <section :if={@kit} id="kit-delete" class="mt-8">
          <h2 class="heading">Delete the kit</h2>
          <p>Its items stay, and so do the activities they went on.</p>
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

    lines = ActivityEquipmentLive.put_typed(socket.assigns.lines, params)
    {:noreply, socket |> assign(lines: lines) |> assign_form(changeset)}
  end

  def handle_event("save", params, socket) do
    team = socket.assigns.current_team
    lines = ActivityEquipmentLive.put_typed(socket.assigns.lines, params)

    kit_lines =
      Enum.map(lines, fn line ->
        minutes =
          if EquipmentItem.takes_hours?(line.item),
            do: Service.Convert.hours_to_minutes(line.hours),
            else: 0

        %{equipment_item_id: line.item.id, minutes: minutes}
      end)

    tag_ids = Enum.map(socket.assigns.tags, & &1.id)

    case SaveKit.save(team, socket.assigns.kit, params["kit"] || %{}, kit_lines, tag_ids) do
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

    minutes =
      if EquipmentItem.takes_hours?(item), do: ActivityEquipmentLive.default_minutes(), else: 0

    lines = ActivityEquipmentLive.add_lines(socket.assigns.lines, [{item, minutes}])
    results = Enum.reject(socket.assigns.results, &(&1.id == item.id))
    {:noreply, assign(socket, lines: lines, results: results)}
  end

  def handle_event("remove-line", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, lines: ActivityEquipmentLive.remove_line(socket.assigns.lines, id))}

  def handle_event("search-tags", %{"tag_q" => q}, socket),
    do: {:noreply, assign(socket, tag_q: q)}

  def handle_event("add-tag", %{"id" => id}, socket) do
    tag = Enum.find(socket.assigns.all_tags, &(Integer.to_string(&1.id) == id))
    tags = (socket.assigns.tags ++ List.wrap(tag)) |> Enum.uniq() |> Enum.sort_by(&tag_sort/1)
    {:noreply, assign(socket, tags: tags)}
  end

  def handle_event("remove-tag", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, tags: Enum.reject(socket.assigns.tags, &(Integer.to_string(&1.id) == id)))}

  attr :q, :string, required: true
  attr :tags, :list, required: true

  defp tag_search(assigns) do
    ~H"""
    <.form for={%{}} id="tag-search-form" phx-change="search-tags" phx-submit="search-tags">
      <.input
        id="tag-search"
        name="tag_q"
        value={@q}
        label="Search"
        placeholder="Part of the tag's name"
        phx-debounce="200"
        autocomplete="off"
      />
    </.form>
    <ul :if={@tags != []} id="tag-search-results" class="action-list">
      <li :for={tag <- @tags}>
        <.button
          id={"tag-add-#{tag.id}"}
          type="button"
          size={:sm}
          variant={:secondary}
          phx-click="add-tag"
          phx-value-id={tag.id}
        >
          Add
        </.button>
        {tag.title}
      </li>
    </ul>
    <p :if={@q != "" and @tags == []} class="hint">No tags match "{@q}".</p>
    """
  end

  @doc "The team's tags not in the kit yet whose title contains `q`, A to Z."
  def tag_results(all_tags, chosen, q) do
    q = q |> String.trim() |> String.downcase()
    chosen = MapSet.new(chosen, & &1.id)

    Enum.filter(all_tags, fn tag ->
      not MapSet.member?(chosen, tag.id) and String.contains?(String.downcase(tag.title), q)
    end)
  end

  defp tag_sort(tag), do: String.downcase(tag.title)
end
