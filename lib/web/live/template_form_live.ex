defmodule Web.TemplateFormLive do
  use Web, :live_view_app_layout

  import Web.ActivityEquipmentLive, only: [lines_table: 1, item_search: 1]
  import Web.ActivityTemplateLive, only: [tags_to_add: 1, groups_to_add: 1]
  import Web.Components.CustomFields, only: [custom_field_inputs: 1]

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.Group
  alias App.Model.Tag
  alias App.Model.Template
  alias App.Operation.SaveTemplate
  alias App.ViewModel.ActivityFormViewModel
  alias Web.ActivityEquipmentLive
  alias Web.ActivityTemplateLive
  alias Web.Components.PlaceBox

  # Adding a template, and its change pages, one per part (#307): Change template for its
  # name and kind, then Change items with their usual hours (#271), Change tags, Change
  # groups whose members it adds (#162), Change fields for its kind's D4H custom
  # fields, and Change details for the activity it starts (#746). Each saves only what it
  # shows. The live action names the page.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    template = if id = params["id"], do: Template.find!(team, id)
    action = socket.assigns.live_action

    socket =
      socket
      |> assign(template: template, page_title: page_title(action, template))
      |> assign(values: (template && template.custom_values) || %{})
      |> assign_part(action, template)
      |> assign_form(Template.build_changeset(template || %Template{}, %{}))
      |> assign_details_form(action, Template.build_details_changeset(template || %Template{}))

    {:ok, socket}
  end

  # Change details has a form of its own, the activity's details.
  defp assign_details_form(socket, :details, changeset),
    do: assign(socket, form: to_form(changeset, as: "template"))

  defp assign_details_form(socket, _action, _changeset), do: socket

  defp page_title(:new, nil), do: "Add template"
  defp page_title(:edit, template), do: "Change #{template.title}"
  defp page_title(:items, template), do: "Change items for #{template.title}"
  defp page_title(:tags, template), do: "Change tags for #{template.title}"
  defp page_title(:groups, template), do: "Change groups for #{template.title}"
  defp page_title(:fields, template), do: "Change fields for #{template.title}"
  defp page_title(:details, template), do: "Change details for #{template.title}"

  defp assign_part(socket, :items, template),
    do: assign(socket, lines: template_lines(template), q: "", results: [])

  defp assign_part(socket, :tags, template) do
    team_id = socket.assigns.current_team.id

    assign(socket,
      tags: Template.tags(template),
      all_tags: SaveTemplate.taggable(socket.assigns.current_team, Tag.get_all(team_id)),
      tag_q: "",
      tag_uses: Tag.use_counts(team_id, a_year_ago())
    )
  end

  defp assign_part(socket, :groups, template),
    do:
      assign(socket,
        groups: Template.groups(template),
        all_groups: Group.get_all(socket.assigns.current_team.id)
      )

  defp assign_part(socket, :details, _template), do: assign(socket, params: %{})

  defp assign_part(socket, _action, _template), do: socket

  defp template_lines(template) do
    template.template_items
    |> Enum.sort_by(&String.downcase(&1.equipment_item.title))
    |> Enum.map(&{&1.equipment_item, &1.minutes})
    |> then(&ActivityEquipmentLive.add_lines([], &1))
  end

  # The fields follow the kind the form holds now.
  defp assign_form(socket, changeset) do
    kind = Ecto.Changeset.get_field(changeset, :activity_kind)
    fields = if kind, do: CustomField.get_all(socket.assigns.current_team.id, kind), else: []
    assign(socket, form: to_form(changeset, as: "template"), fields: fields)
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Templates" path={~p"/teams/#{@current_team}/templates"} />
      <:item
        :if={@template}
        label={@template.title}
        path={~p"/teams/#{@current_team}/templates/#{@template.id}"}
      />
      <:item label={crumb(@live_action)} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <div :if={@live_action in [:items, :tags, :groups]} class="content-wrapper">
      <aside class="content-1/3">
        <section :if={@live_action == :items} id="template-search">
          <h2 class="heading">Find an item</h2>
          <.item_search q={@q} results={@results} />
        </section>

        <section :if={@live_action == :tags} id="template-tag-search">
          <h2 class="heading">Find a tag</h2>
          <.tag_search q={@tag_q} results={tag_results(@all_tags, @tags, @tag_q, @tag_uses)} />
        </section>

        <section :if={@live_action == :groups} id="template-group-search">
          <h2 class="heading">Groups</h2>
          <.table
            :if={group_results(@all_groups, @groups) != []}
            id="group-results"
            rows={group_results(@all_groups, @groups)}
            row_id={&"group-result-#{&1.id}"}
            class="table-striped"
          >
            <%!-- No link: leaving the form drops the changes. --%>
            <:col :let={group} label="Group">
              <.group_cell group={group} link={false} />
            </:col>
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
            The team has no groups yet.
          </p>
        </section>
      </aside>
      <main class="content-2/3">
        <.part_form {assigns} />
      </main>
    </div>

    <div :if={@live_action in [:new, :edit, :fields, :details]} class="measure">
      <.part_form {assigns} />
    </div>
    """
  end

  defp crumb(:new), do: "Add template"
  defp crumb(:edit), do: "Change"
  defp crumb(:items), do: "Change items"
  defp crumb(:tags), do: "Change tags"
  defp crumb(:groups), do: "Change groups"
  defp crumb(:fields), do: "Change fields"
  defp crumb(:details), do: "Change details"

  defp part_form(assigns) do
    ~H"""
    <.form for={@form} id="template-form" phx-change="validate" phx-submit="save">
      <.part {assigns} />
      <.form_actions :if={@live_action != :fields or @fields != []}>
        <.button id="template-save" variant={:success}>{save_label(@live_action)}</.button>
        <.button id="template-cancel" navigate={back_path(@current_team, @template)}>
          Cancel
        </.button>
      </.form_actions>
    </.form>
    """
  end

  defp save_label(:new), do: "Add template"
  defp save_label(:edit), do: "Save template"
  defp save_label(:items), do: "Save items"
  defp save_label(:tags), do: "Save tags"
  defp save_label(:groups), do: "Save groups"
  defp save_label(:fields), do: "Save fields"
  defp save_label(:details), do: "Save details"

  defp part(%{live_action: action} = assigns) when action in [:new, :edit] do
    ~H"""
    <.error_summary form={@form} />
    <.input field={@form[:title]} label="Name">Such as "Truck 1" or "Boat training".</.input>
    <.input
      field={@form[:activity_kind]}
      type="select"
      label="Kind"
      options={Template.kind_options()}
    >
      {kind_hint(@current_team, @template)}
    </.input>
    """
  end

  defp part(%{live_action: :items} = assigns) do
    ~H"""
    <h2 class="heading">Items · {length(@lines)}</h2>
    <p class="hint mb-4">
      The hours are what each item adds to an activity. You can change them when you apply the template.
    </p>
    <.lines_table :if={@lines != []} id="template-lines" lines={@lines} />
    <p :if={@lines == []} id="template-no-items" class="hint mb-4">
      Find items to add.
    </p>
    """
  end

  defp part(%{live_action: :tags} = assigns) do
    ~H"""
    <h2 class="heading">Tags · {length(@tags)}</h2>
    <p class="hint mb-4">
      Applying the template adds these tags to the activity and keeps the tags it has. The hours tag comes from Tax credit hours, on <.a navigate={
        ~p"/teams/#{@current_team}/templates/#{@template.id}/details/edit"
      }>Change details</.a>.
    </p>
    <.tags_to_add :if={@tags != []} id="template-tags" tags={@tags} />
    <p :if={@tags == []} id="template-no-tags" class="hint mb-4">
      Find tags to add.
    </p>
    """
  end

  defp part(%{live_action: :groups} = assigns) do
    ~H"""
    <h2 class="heading">Groups · {length(@groups)}</h2>
    <p class="hint mb-4">
      Applying the template adds each member of these groups to the activity, as No reply.
    </p>
    <.groups_to_add :if={@groups != []} id="template-groups" groups={@groups} />
    <p :if={@groups == []} id="template-no-groups" class="hint mb-4">
      Add groups whose members the template adds.
    </p>
    """
  end

  defp part(%{live_action: :fields} = assigns) do
    ~H"""
    <section :if={@fields != []} id="template-fields">
      <p class="hint mb-6">
        Applying the template fills in the fields the activity has empty. Leave one blank to leave it alone.
      </p>
      <.custom_field_inputs fields={@fields} values={@values} />
    </section>
    <p :if={@fields == []} id="template-no-fields">
      {no_fields_text(@current_team, @template)}
    </p>
    """
  end

  defp part(%{live_action: :details} = assigns) do
    ~H"""
    <p class="lead">
      These fill the Add activity form when someone picks this template. The date is picked there, and anything can be changed before saving. The kind is on Change template.
    </p>
    <.error_summary form={@form} />
    <.input field={@form[:activity_title]} label="Title (optional)">
      Leave blank to use the template's name.
    </.input>
    <div class="max-w-xs">
      <.input field={@form[:start_time]} type="time" label="Start time (optional)" />
    </div>
    <.duration_input
      field={@form[:duration]}
      minutes={@form[:duration_minutes]}
      label="Duration (optional)"
    />
    <.live_component
      module={PlaceBox}
      id="template"
      team={@current_team}
      field={@form[:place]}
      coordinate={@form[:coordinate]}
      label="Address (optional)"
      kind={PlaceBox.map_kind(@template.activity_kind)}
    />
    <.input
      field={@form[:hours]}
      type="select"
      label="Tax credit hours"
      options={ActivityFormViewModel.hours()}
    >
      {hours_hint(@current_team)}
    </.input>
    <.input
      field={@form[:description]}
      type="rich_text"
      label="Description (optional)"
    />
    """
  end

  defp hours_hint(team) do
    hours_tags = Activity.hours_tags(team)

    "Which hours the activity counts for on tax credit letters. Sets the #{hours_tags.primary} or #{hours_tags.secondary} tag."
  end

  defp kind_hint(team, %Template{custom_values: values}) when map_size(values) > 0,
    do:
      "Pick a kind to fill in its #{D4H.service_name(team)} fields. A new kind drops the #{Service.Format.count(map_size(values), one: "%d field value", many: "%d field values")}."

  defp kind_hint(team, _template),
    do: "Pick a kind to fill in its #{D4H.service_name(team)} fields."

  defp no_fields_text(_team, %Template{activity_kind: nil}),
    do: "This template is for any kind. Pick a kind on Change template to fill in its fields."

  defp no_fields_text(team, template),
    do: "#{D4H.service_name(team)} has no fields for this #{template.activity_kind}."

  def handle_event("validate", params, %{assigns: %{live_action: :details}} = socket) do
    details = params["template"] || %{}
    socket = socket |> assign(params: details) |> validate_details(details)

    if params["_target"] == ["template", "place"],
      do: PlaceBox.typed("template", details["place"])

    {:noreply, socket}
  end

  def handle_event("validate", params, socket) do
    changeset =
      (socket.assigns.template || %Template{})
      |> Template.build_changeset(params["template"] || %{})
      |> Map.put(:action, :validate)

    {:noreply, socket |> put_typed(params) |> put_values(params) |> assign_form(changeset)}
  end

  def handle_event("save", params, %{assigns: %{live_action: :details}} = socket) do
    %{current_team: team, template: template} = socket.assigns

    case SaveTemplate.save_details(team, template, params["template"] || %{}) do
      {:ok, template} -> {:noreply, saved(socket, template)}
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset, as: "template"))}
    end
  end

  def handle_event("save", params, socket) do
    %{current_team: team, template: template, live_action: action} = socket.assigns
    socket = put_typed(socket, params)

    case SaveTemplate.save(
           team,
           template,
           params["template"] || %{},
           parts(action, socket.assigns, params)
         ) do
      {:ok, template} ->
        {:noreply, saved(socket, template)}

      {:error, changeset} ->
        {:noreply, socket |> put_values(params) |> assign_form(changeset)}
    end
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

  def handle_event("add-tag", %{"id" => id}, socket),
    do:
      {:noreply, assign(socket, tags: add_tag(socket.assigns.tags, socket.assigns.all_tags, id))}

  def handle_event("remove-tag", %{"id" => id}, socket),
    do: {:noreply, assign(socket, tags: remove_tag(socket.assigns.tags, id))}

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

  # A place picked, or its pin removed (#610).
  def handle_info({PlaceBox, values}, socket) do
    params = Map.merge(socket.assigns.params, values)
    {:noreply, socket |> assign(params: params) |> validate_details(params)}
  end

  defp validate_details(socket, params) do
    changeset =
      socket.assigns.template
      |> Template.build_details_changeset(params)
      |> Map.put(:action, :validate)

    assign(socket, form: to_form(changeset, as: "template"))
  end

  defp saved(socket, template) do
    socket
    |> put_flash(:info, "Saved the #{template.title} template.")
    |> push_navigate(to: ~p"/teams/#{socket.assigns.current_team}/templates/#{template.id}")
  end

  defp back_path(team, nil), do: ~p"/teams/#{team}/templates"
  defp back_path(team, template), do: ~p"/teams/#{team}/templates/#{template.id}"

  # Keeps what was typed in the fields when the page renders again.
  defp put_values(socket, params),
    do: assign(socket, values: Map.merge(socket.assigns.values, params["fields"] || %{}))

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

  @doc "The tags with the one whose id is `id` added, by title. Shared with ActivityTagsLive."
  def add_tag(tags, all_tags, id) do
    tag = Enum.find(all_tags, &(Integer.to_string(&1.id) == id))
    (tags ++ List.wrap(tag)) |> Enum.uniq() |> Enum.sort_by(&tag_sort/1)
  end

  @doc "The tags without the one whose id is `id`."
  def remove_tag(tags, id), do: Enum.reject(tags, &(Integer.to_string(&1.id) == id))

  def tag_sort(tag), do: String.downcase(tag.title)

  # What the page saves, besides the name and kind.
  defp parts(:items, assigns, _params), do: [items: Enum.map(assigns.lines, &template_line/1)]
  defp parts(:tags, assigns, _params), do: [tag_ids: Enum.map(assigns.tags, & &1.id)]
  defp parts(:groups, assigns, _params), do: [group_ids: Enum.map(assigns.groups, & &1.id)]
  defp parts(:fields, _assigns, params), do: [fields: params["fields"] || %{}]
  defp parts(_action, _assigns, _params), do: []

  # The hours typed on Change items.
  defp put_typed(%{assigns: %{live_action: :items}} = socket, params),
    do: assign(socket, lines: ActivityEquipmentLive.put_typed(socket.assigns.lines, params))

  defp put_typed(socket, _params), do: socket

  defp template_line(line) do
    minutes =
      if EquipmentItem.takes_hours?(line.item),
        do: Service.Convert.hours_to_minutes(line.hours),
        else: 0

    %{equipment_item_id: line.item.id, minutes: minutes}
  end
end
