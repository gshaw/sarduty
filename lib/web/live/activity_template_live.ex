defmodule Web.ActivityTemplateLive do
  use Web, :live_view_app_layout

  import Web.ActivityEquipmentLive, only: [lines_table: 1]

  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.Tag
  alias App.Model.Template
  alias App.Operation.ApplyTemplate
  alias App.Operation.SaveCustomFields
  alias Web.ActivityEquipmentLive

  # Applying templates to an activity (#162). Each template adds its items, with hours to
  # check, its tags, its custom field values, its groups, and its Enough at and Full at
  # (#447) to one list. Sending is ApplyTemplate.call/5.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    activity = Web.ActivityLive.fetch_activity(team, id)

    if activity.deleted_at do
      {:ok, Web.ActivityLive.leave_deleted(socket, activity)}
    else
      used =
        activity |> EquipmentUsage.for_activity() |> MapSet.new(& &1.equipment_item_id)

      socket =
        socket
        |> assign(page_title: "Apply a template", activity: activity, used: used)
        |> assign(lines: [], tags: [], groups: [], fills: %{}, fields_locked?: false)
        |> assign(numbers: nil, numbers_left_out: nil)
        |> assign(fields: CustomField.get_all(team.id, activity.activity_kind))
        |> assign(templates: Template.get_all(team.id))

      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item label={@activity.ref_id} path={~p"/teams/#{@current_team}/activities/#{@activity.id}"} />
      <:item label="Apply a template" />
    </.breadcrumbs>
    <h1 class="title">Apply a template</h1>
    <p class="lead">{@activity.title}</p>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <section id="templates">
          <h2 class="heading">Templates</h2>
          <.table
            :if={@templates != []}
            id="templates-table"
            rows={@templates}
            row_id={&"template-#{&1.id}"}
            class="table-striped"
          >
            <:col :let={template} label="Template">
              {template.title}
              <div class="hint">{template_contents(template)}</div>
            </:col>
            <:col :let={template} label="" class="w-px whitespace-nowrap">
              <.button
                id={"add-template-#{template.id}"}
                type="button"
                size={:sm}
                phx-click="add-template"
                phx-value-id={template.id}
              >
                Add
              </.button>
            </:col>
          </.table>
          <p class="hint mt-4">
            <.a navigate={~p"/teams/#{@current_team}/templates"}>{if @templates == [],
              do: "Add a template",
              else: "Change templates"}</.a>
            for items, tags, groups, and fields that go together.
          </p>
        </section>
      </aside>

      <main class="content-2/3">
        <section id="template-to-add">
          <h2 class="heading">To add</h2>
          <.form
            :if={anything?(assigns)}
            for={%{}}
            id="template-lines"
            phx-change="hours"
            phx-submit="send"
          >
            <div :if={@fills != %{}} id="template-fields" class="mb-4">
              <h3 class="subheading">Fields</h3>
              <p class="hint mb-2">
                These fill in fields the activity has empty. When two templates fill one field, the first one added wins.
              </p>
              <.fields_to_fill
                id="template-fields-table"
                rows={CustomField.rows(@fields, @fills, @current_team.timezone, restricted: true)}
              />
            </div>
            <div :if={@numbers} id="template-numbers" class="mb-4">
              <h3 class="subheading">Enough at and Full at</h3>
              <p class="hint mb-2">
                These fill in an activity with neither. When two templates have them, the first one added wins.
              </p>
              <.numbers_to_set id="template-numbers-table" numbers={@numbers} />
            </div>
            <.lines_table :if={@lines != []} id="template-lines-table" lines={@lines} km />
            <div :if={@tags != []} id="template-tags" class="mt-4">
              <h3 class="subheading">Tags</h3>
              <p class="hint mb-2">The activity keeps the tags it has.</p>
              <.tags_to_add id="template-tags-table" tags={@tags} />
            </div>
            <div :if={@groups != []} id="template-groups" class="mt-4">
              <h3 class="subheading">Groups</h3>
              <p class="hint mb-2">
                SAR Duty adds each member of these groups who is not on the activity, as No reply. Nobody is emailed.
              </p>
              <.groups_to_add id="template-groups-table" groups={@groups} />
            </div>
            <.form_actions>
              <.button id="template-send" variant={:success} phx-disable-with="Adding…">
                Add to activity
              </.button>
              <.button
                id="template-cancel"
                navigate={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
              >
                Cancel
              </.button>
            </.form_actions>
          </.form>
          <p :if={!anything?(assigns)} id="template-nothing-to-add" class="hint">
            Add one or more templates. Check the hours and a vehicle's km, then add them to the activity.
          </p>
          <p :if={@fields_locked?} id="template-fields-locked" class="hint mt-4">
            The templates' fields are left out: the activity is published.
          </p>
          <p :if={@numbers_left_out} id="template-numbers-left-out" class="hint mt-4">
            The templates' Enough at and Full at are left out: {@numbers_left_out}
          </p>
        </section>
      </main>
    </div>
    """
  end

  defp anything?(assigns),
    do:
      assigns.lines != [] or assigns.tags != [] or assigns.groups != [] or assigns.fills != %{} or
        assigns.numbers != nil

  attr :id, :string, required: true
  attr :numbers, :map, required: true, doc: "from ApplyTemplate.numbers/4"

  # One row: the two numbers go as a pair.
  defp numbers_to_set(assigns) do
    ~H"""
    <.table id={@id} rows={[@numbers]} row_id={fn _numbers -> "numbers" end} class="table-striped">
      <:col :let={numbers} label="Enough at">{numbers.enough_at || "None"}</:col>
      <:col :let={numbers} label="Full at">{numbers.full_at || "None"}</:col>
      <:col label="" class="w-px whitespace-nowrap">
        <.button id="numbers-remove" type="button" size={:sm} phx-click="remove-numbers">
          Remove
        </.button>
      </:col>
    </.table>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "from CustomField.rows/4"

  defp fields_to_fill(assigns) do
    ~H"""
    <.table
      id={@id}
      rows={@rows}
      row_id={&"field-#{&1.field.d4h_custom_field_id}"}
      class="table-striped"
    >
      <:col :let={row} label="Field">{row.field.title}</:col>
      <:col :let={row} label="Value">{row.text}</:col>
      <:col :let={row} label="" class="w-px whitespace-nowrap">
        <.button
          id={"field-remove-#{row.field.d4h_custom_field_id}"}
          type="button"
          size={:sm}
          phx-click="remove-field"
          phx-value-id={row.field.d4h_custom_field_id}
        >
          Remove
        </.button>
      </:col>
    </.table>
    """
  end

  attr :id, :string, required: true
  attr :tags, :list, required: true

  @doc "Tags about to be added, each with a remove button. Shared with the template form and ActivityTagsLive."
  def tags_to_add(assigns) do
    ~H"""
    <.table id={@id} rows={@tags} row_id={&"tag-#{&1.id}"} class="table-striped">
      <:col :let={tag} label="Tag">
        <.badge kind={:outline}>{tag.title}</.badge>
      </:col>
      <:col :let={tag} label="" class="w-px whitespace-nowrap">
        <.button
          id={"tag-remove-#{tag.id}"}
          type="button"
          size={:sm}
          phx-click="remove-tag"
          phx-value-id={tag.id}
        >
          Remove
        </.button>
      </:col>
    </.table>
    """
  end

  attr :id, :string, required: true
  attr :groups, :list, required: true

  @doc "Groups whose members are about to be added, each with a remove button. Shared with the template form."
  def groups_to_add(assigns) do
    ~H"""
    <.table id={@id} rows={@groups} row_id={&"group-#{&1.id}"} class="table-striped">
      <%!-- No link: leaving the page drops the picks. --%>
      <:col :let={group} label="Group">
        <.group_cell group={group} link={false} />
      </:col>
      <:col :let={group} label="" class="w-px whitespace-nowrap">
        <.button
          id={"group-remove-#{group.id}"}
          type="button"
          size={:sm}
          phx-click="remove-group"
          phx-value-id={group.id}
        >
          Remove
        </.button>
      </:col>
    </.table>
    """
  end

  @doc ~s(What a template holds, as "Incident: 3 items, 2 tags, 1 group, 5 fields".)
  def template_contents(template) do
    tags = length(template.template_tags)
    groups = length(template.template_groups)
    fields = map_size(template.custom_values || %{})

    [count_items(length(template.template_items))]
    |> Kernel.++(if tags > 0, do: [count_tags(tags)], else: [])
    |> Kernel.++(if groups > 0, do: [count_groups(groups)], else: [])
    |> Kernel.++(if fields > 0, do: [count_fields(fields)], else: [])
    |> Enum.join(", ")
    |> then(&if(template.activity_kind, do: "#{Template.kind_label(template)}: #{&1}", else: &1))
  end

  @doc "`groups` with a template's `new` groups added, each once, A to Z."
  def add_groups(groups, new),
    do: (groups ++ new) |> Enum.uniq_by(& &1.id) |> Enum.sort_by(&String.downcase(&1.title))

  def handle_event("add-template", %{"id" => id}, socket) do
    %{activity: activity, lines: lines, used: used} = socket.assigns
    template = Template.find!(socket.assigns.current_team, id)

    new =
      for line <- template.template_items, EquipmentItem.in_service?(line.equipment_item) do
        {line.equipment_item, line.minutes}
      end

    socket =
      socket
      |> assign(
        lines: ActivityEquipmentLive.add_lines(lines, new, used),
        tags:
          ApplyTemplate.add_tags(socket.assigns.tags, apply_tags(socket, template), activity.tags),
        groups: add_groups(socket.assigns.groups, Template.groups(template))
      )
      |> add_fills(template)
      |> add_numbers(template)

    {:noreply, socket}
  end

  def handle_event("hours", params, socket),
    do:
      {:noreply,
       assign(socket, lines: ActivityEquipmentLive.put_typed(socket.assigns.lines, params))}

  def handle_event("remove-line", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, lines: ActivityEquipmentLive.remove_line(socket.assigns.lines, id))}

  def handle_event("remove-tag", %{"id" => id}, socket),
    do: {:noreply, assign(socket, tags: reject_id(socket.assigns.tags, id))}

  def handle_event("remove-group", %{"id" => id}, socket),
    do: {:noreply, assign(socket, groups: reject_id(socket.assigns.groups, id))}

  def handle_event("remove-numbers", _params, socket),
    do: {:noreply, assign(socket, numbers: nil)}

  def handle_event("remove-field", %{"id" => id}, socket),
    do: {:noreply, assign(socket, fills: Map.delete(socket.assigns.fills, id))}

  def handle_event("send", params, socket) do
    lines =
      socket.assigns.lines
      |> ActivityEquipmentLive.put_typed(params)
      |> Enum.map(&ActivityEquipmentLive.to_add/1)

    %{current_team: team, current_user: user, activity: activity} = socket.assigns

    adds =
      socket.assigns |> Map.take([:fills, :tags, :groups, :numbers]) |> Map.put(:lines, lines)

    case ApplyTemplate.call(team, user, activity, adds, DateTime.utc_now()) do
      {:ok, kind, text} ->
        socket =
          socket
          |> put_flash(kind, text)
          |> push_navigate(to: ~p"/teams/#{team}/activities/#{activity.id}")

        {:noreply, socket}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  # A published activity's fields are locked, so a template's are left out and said so.
  # The first template picked sets the hours, as for a field two of them set.
  defp apply_tags(socket, template) do
    %{current_team: team, activity: activity, tags: picked} = socket.assigns
    titles = (activity.tags || []) ++ Enum.map(picked, & &1.title)
    Template.apply_tags(template, titles, Tag.get_all(team.id), Activity.hours_tags(team))
  end

  defp add_fills(socket, template) do
    %{activity: activity, fields: fields, fills: fills} = socket.assigns
    added = SaveCustomFields.fill_empty(fills, activity, fields, template.custom_values)

    cond do
      added == fills -> socket
      Activity.locked?(activity) -> assign(socket, fields_locked?: true)
      true -> assign(socket, fills: added)
    end
  end

  # A template with numbers it can't set says why, as for a published activity's fields.
  defp add_numbers(socket, template) do
    %{activity: activity, numbers: numbers} = socket.assigns
    now = DateTime.utc_now()

    cond do
      template.enough_at == nil and template.full_at == nil ->
        socket

      numbers = ApplyTemplate.numbers(numbers, template, activity, now) ->
        assign(socket, numbers: numbers)

      not Activity.open?(activity, now) ->
        assign(socket, numbers_left_out: "the activity has started.")

      true ->
        assign(socket, numbers_left_out: "the activity has its own.")
    end
  end

  defp reject_id(records, id), do: Enum.reject(records, &(Integer.to_string(&1.id) == id))

  defp count_items(n), do: Service.Format.count(n, one: "%d item", many: "%d items")
  defp count_tags(n), do: Service.Format.count(n, one: "%d tag", many: "%d tags")
  defp count_groups(n), do: Service.Format.count(n, one: "%d group", many: "%d groups")
  defp count_fields(n), do: Service.Format.count(n, one: "%d field", many: "%d fields")
end
