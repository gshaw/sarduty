defmodule Web.TemplateFormLive do
  use Web, :live_view_app_layout

  import Web.ActivityEquipmentLive, only: [lines_table: 1, item_search: 1]
  import Web.ActivityTemplateLive, only: [tags_to_add: 1, groups_to_invite: 1]

  alias App.Adapter.D4H
  alias App.Model.EquipmentItem
  alias App.Model.Group
  alias App.Model.Tag
  alias App.Model.Template
  alias App.Operation.SaveTemplate
  alias Web.ActivityEquipmentLive
  alias Web.ActivityTemplateLive

  # Adding and changing a template: its name, its items with their usual hours (#271), its
  # tags, and the groups it invites (#162). Tags and groups come from the sync's copy of
  # the team's D4H records.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    template = if id = params["id"], do: Template.find!(team, id)

    socket =
      socket
      |> assign(template: template, lines: template_lines(template), q: "", results: [])
      |> assign(
        tags: if(template, do: Template.tags(template), else: []),
        all_tags: Tag.get_all(team.id)
      )
      |> assign(tag_q: "", tag_uses: Tag.use_counts(team.id, a_year_ago()))
      |> assign(
        groups: if(template, do: Template.groups(template), else: []),
        all_groups: Group.get_all(team.id)
      )
      |> assign(page_title: if(template, do: template.title, else: "Add template"))
      |> assign(service: D4H.service_name(team))
      |> assign_form(Template.build_changeset(template || %Template{}, %{}))

    {:ok, socket}
  end

  defp template_lines(nil), do: []

  defp template_lines(template) do
    template.template_items
    |> Enum.sort_by(&String.downcase(&1.equipment_item.title))
    |> Enum.map(&{&1.equipment_item, &1.minutes})
    |> then(&ActivityEquipmentLive.add_lines([], &1))
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "template"))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Templates" path={~p"/teams/#{@current_team}/templates"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <section id="template-search" class="mb-8">
          <h2 class="heading">Find an item</h2>
          <.item_search q={@q} results={@results} />
        </section>

        <section id="template-tag-search">
          <h2 class="heading">Find a tag</h2>
          <.tag_search q={@tag_q} results={tag_results(@all_tags, @tags, @tag_q, @tag_uses)} />
        </section>

        <section id="template-group-search" class="mt-8">
          <h2 class="heading">Groups</h2>
          <.table
            :if={group_results(@all_groups, @groups) != []}
            id="group-results"
            rows={group_results(@all_groups, @groups)}
            row_id={&"group-result-#{&1.id}"}
            class="table-striped"
          >
            <:col :let={group} label="Group">{group.title}</:col>
            <:col :let={group} label="" class="w-px whitespace-nowrap">
              <.button
                id={"group-add-#{group.id}"}
                type="button"
                size={:sm}
                phx-click="add-group"
                phx-value-id={group.id}
              >
                Add
              </.button>
            </:col>
          </.table>
          <p :if={@all_groups == []} class="hint">
            The team has no groups in {@service}.
          </p>
        </section>
      </aside>
      <main class="content-2/3">
        <.form for={@form} id="template-form" phx-change="validate" phx-submit="save">
          <.error_summary form={@form} />
          <.input field={@form[:title]} label="Name">Such as "Truck 1" or "Boat training".</.input>

          <h2 class="heading">Items · {length(@lines)}</h2>
          <p class="hint mb-4">
            The hours are what each item adds to an activity. You can change them when you apply the template.
          </p>
          <.lines_table :if={@lines != []} id="template-lines" lines={@lines} />
          <p :if={@lines == []} id="template-no-items" class="hint mb-4">
            Find items to add.
          </p>

          <h2 class="heading mt-8">Tags · {length(@tags)}</h2>
          <p class="hint mb-4">
            Applying the template adds these tags to the activity and keeps the tags it has.
          </p>
          <.tags_to_add :if={@tags != []} id="template-tags" tags={@tags} />
          <p :if={@tags == []} id="template-no-tags" class="hint mb-4">
            Find tags to add.
          </p>

          <h2 class="heading mt-8">Invite · {length(@groups)}</h2>
          <p class="hint mb-4">
            Applying the template invites each member of these groups to the activity. They answer in {@service}.
          </p>
          <.groups_to_invite :if={@groups != []} id="template-groups" groups={@groups} />
          <p :if={@groups == []} id="template-no-groups" class="hint mb-4">
            Add groups to invite.
          </p>

          <.form_actions>
            <.button id="template-save" variant={:success}>{if @template,
              do: "Save template",
              else: "Add template"}</.button>
          </.form_actions>
        </.form>

        <section :if={@template} id="template-delete" class="mt-8">
          <h2 class="heading">Delete the template</h2>
          <p>Its items stay, and so do the activities they went on.</p>
          <.button
            id="template-delete-button"
            type="button"
            variant={:danger}
            phx-click="delete"
            data-confirm={"Delete the #{@template.title} template?"}
          >
            Delete template
          </.button>
        </section>
      </main>
    </div>
    """
  end

  def handle_event("validate", params, socket) do
    changeset =
      (socket.assigns.template || %Template{})
      |> Template.build_changeset(params["template"] || %{})
      |> Map.put(:action, :validate)

    lines = ActivityEquipmentLive.put_typed(socket.assigns.lines, params)
    {:noreply, socket |> assign(lines: lines) |> assign_form(changeset)}
  end

  def handle_event("save", params, socket) do
    team = socket.assigns.current_team
    lines = ActivityEquipmentLive.put_typed(socket.assigns.lines, params)

    case save_template(socket.assigns, params["template"] || %{}, lines) do
      {:ok, template} ->
        socket =
          socket
          |> put_flash(:info, "Saved the #{template.title} template.")
          |> push_navigate(to: ~p"/teams/#{team}/templates")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, socket |> assign(lines: lines) |> assign_form(changeset)}
    end
  end

  def handle_event("delete", _params, socket) do
    %{current_team: team, template: template} = socket.assigns
    :ok = SaveTemplate.delete(team, template)

    socket =
      socket
      |> put_flash(:info, "Deleted the #{template.title} template.")
      |> push_navigate(to: ~p"/teams/#{team}/templates")

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

  def handle_event("add-group", %{"id" => id}, socket) do
    group = Enum.find(socket.assigns.all_groups, &(Integer.to_string(&1.id) == id))
    groups = ActivityTemplateLive.add_groups(socket.assigns.groups, List.wrap(group))
    {:noreply, assign(socket, groups: groups)}
  end

  def handle_event("remove-group", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket,
         groups: Enum.reject(socket.assigns.groups, &(Integer.to_string(&1.id) == id))
       )}

  @doc "The team's groups to offer, leaving out the template's."
  def group_results(all_groups, chosen) do
    chosen = MapSet.new(chosen, & &1.id)
    Enum.reject(all_groups, &MapSet.member?(chosen, &1.id))
  end

  attr :q, :string, required: true
  attr :results, :map, required: true, doc: "from tag_results/4"

  @doc "A search box for the team's tags, with an add button for each. Shared with ActivityTagsLive."
  def tag_search(assigns) do
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
    <p :if={@q == "" and @results.tags != []} id="tag-most-used" class="hint mb-2">
      Used most in the last year
    </p>
    <.table
      :if={@results.tags != []}
      id="tag-search-results"
      rows={@results.tags}
      row_id={&"tag-result-#{&1.id}"}
      class="table-striped"
    >
      <:col :let={tag} label="Tag">
        <.badge kind={:outline}>{tag.title}</.badge>
      </:col>
      <:col :let={tag} label="" class="w-px whitespace-nowrap">
        <.button
          id={"tag-add-#{tag.id}"}
          type="button"
          size={:sm}
          phx-click="add-tag"
          phx-value-id={tag.id}
        >
          Add
        </.button>
      </:col>
    </.table>
    <p :if={@results.more > 0} id="tag-more" class="hint mt-2">
      {Service.Format.count(@results.more, one: "%d more tag matches.", many: "%d more tags match.")} Type more of the name.
    </p>
    <p :if={@q != "" and @results.tags == []} class="hint">No tags match "{@q}".</p>
    """
  end

  @most_used 8
  @shown 10

  @doc """
  The tags to offer, leaving out the template's. With no search, the #{@most_used} its
  activities used most in the last year (`uses`, title to count). With one, the first
  #{@shown} matches A to Z, and how many more there are. `%{tags: tags, more: n}`.
  """
  def tag_results(all_tags, chosen, q, uses) do
    q = q |> String.trim() |> String.downcase()
    chosen = MapSet.new(chosen, & &1.id)
    offered = Enum.reject(all_tags, &MapSet.member?(chosen, &1.id))

    if q == "", do: most_used(offered, uses), else: matching(offered, q)
  end

  defp most_used(tags, uses) do
    tags =
      tags
      |> Enum.filter(&(Map.get(uses, &1.title, 0) > 0))
      |> Enum.sort_by(&{-uses[&1.title], tag_sort(&1)})
      |> Enum.take(@most_used)

    %{tags: tags, more: 0}
  end

  defp matching(tags, q) do
    matches = Enum.filter(tags, &String.contains?(String.downcase(&1.title), q))
    %{tags: Enum.take(matches, @shown), more: max(length(matches) - @shown, 0)}
  end

  defp a_year_ago, do: DateTime.add(DateTime.utc_now(), -365, :day)

  def tag_sort(tag), do: String.downcase(tag.title)

  defp save_template(
         %{current_team: team, template: template, tags: tags, groups: groups},
         params,
         lines
       ) do
    lines = Enum.map(lines, &template_line/1)

    SaveTemplate.save(
      team,
      template,
      params,
      lines,
      Enum.map(tags, & &1.id),
      Enum.map(groups, & &1.id)
    )
  end

  defp template_line(line) do
    minutes =
      if EquipmentItem.takes_hours?(line.item),
        do: Service.Convert.hours_to_minutes(line.hours),
        else: 0

    %{equipment_item_id: line.item.id, minutes: minutes}
  end
end
