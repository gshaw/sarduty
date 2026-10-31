defmodule Web.ActivityTemplateLive do
  use Web, :live_view_app_layout

  import Web.ActivityEquipmentLive, only: [lines_table: 1]

  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.Tag
  alias App.Model.Template
  alias App.Operation.ChangeActivityEquipment
  alias App.Operation.InviteMembers
  alias App.Operation.SaveCustomFields
  alias Web.ActivityEquipmentLive

  # Applying templates to an activity (#162). Each template adds its items, with hours to
  # check, its tags, its custom field values, and its groups to one list. Sending fills in
  # the activity's empty fields (#307), writes the items and tags to D4H as equipment
  # usages and the activity's tags, then adds the groups' members (#564).
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
        </section>
      </main>
    </div>
    """
  end

  defp anything?(assigns),
    do: assigns.lines != [] or assigns.tags != [] or assigns.groups != [] or assigns.fills != %{}

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

  @doc """
  `tags` with a template's `new` tags added, A to Z, leaving out any the activity has by
  title (`titles`). The send reads D4H again, so a stale title only means a tag goes
  unlisted.
  """
  def add_tags(tags, new, titles) do
    titles = titles || []

    (tags ++ Enum.reject(new, &(&1.title in titles)))
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&String.downcase(&1.title))
  end

  @doc "`groups` with a template's `new` groups added, each once, A to Z."
  def add_groups(groups, new),
    do: (groups ++ new) |> Enum.uniq_by(& &1.id) |> Enum.sort_by(&String.downcase(&1.title))

  @doc """
  What adding the groups' members did, from InviteMembers.call/6's result: "8 members
  added.", then the rows that did not go and why, then how many were away on `day`. No
  rows and nobody away means everyone was on the activity already.
  """
  def invite_text(%{rows: [], away: []}, _day),
    do: "Everyone in those groups is on the activity already."

  def invite_text(%{rows: rows, away: away}, day),
    do: (InviteMembers.result_lines(rows) ++ away_text(away, day)) |> Enum.join(" ")

  defp away_text([], _day), do: []

  defp away_text(away, day) do
    away
    |> length()
    |> Service.Format.count(
      one: "1 member away on #{day} was left out.",
      many: "%d members away on #{day} were left out."
    )
    |> List.wrap()
  end

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
        tags: add_tags(socket.assigns.tags, apply_tags(socket, template), activity.tags),
        groups: add_groups(socket.assigns.groups, Template.groups(template))
      )
      |> add_fills(template)

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

  def handle_event("remove-field", %{"id" => id}, socket),
    do: {:noreply, assign(socket, fills: Map.delete(socket.assigns.fills, id))}

  def handle_event("send", params, socket) do
    lines =
      socket.assigns.lines
      |> ActivityEquipmentLive.put_typed(params)
      |> Enum.map(&ActivityEquipmentLive.to_add/1)

    case send_all(socket.assigns, lines, DateTime.utc_now()) do
      {:ok, kind, text} ->
        %{current_team: team, activity: activity} = socket.assigns

        socket =
          socket
          |> put_flash(kind, text)
          |> push_navigate(to: ~p"/teams/#{team}/activities/#{activity.id}")

        {:noreply, socket}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  # Fields go first, then equipment and tags; a refusal leaves the rest unsent.
  defp send_all(assigns, lines, now) do
    %{current_team: team, current_user: user, activity: activity, fills: fills} = assigns

    with :ok <- fill_fields(team, activity, fills, user, now),
         {:ok, rows} <- add_after_fields(assigns, lines, now) do
      {kind, text} = invite(team, activity, assigns.groups, user, now, rows)
      {:ok, kind, Enum.join(fields_text(fills) ++ List.wrap(text), " ")}
    end
  end

  # Once the fields went, a refusal leaves the page to say so, as for a refused invite.
  defp add_after_fields(%{fills: fills} = assigns, lines, now) do
    %{current_team: team, current_user: user, activity: activity, tags: tags} = assigns

    case add_equipment(team, activity, lines, tags, user, now) do
      {:error, text} when fills != %{} ->
        {:ok, :error, "#{count_fields(map_size(fills))} filled in. #{text}"}

      result ->
        result
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

  defp fill_fields(_team, _activity, fills, _user, _now) when fills == %{}, do: :ok

  defp fill_fields(team, activity, fills, user, now) do
    case SaveCustomFields.call(team, activity, fills, user, now) do
      {:ok, _activity} -> :ok
      {:error, text} -> {:error, "The fields were not sent. #{text}"}
    end
  end

  defp fields_text(fills) when fills == %{}, do: []

  defp fields_text(fills),
    do: [count_fields(map_size(fills)) <> " filled in."]

  defp reject_id(records, id), do: Enum.reject(records, &(Integer.to_string(&1.id) == id))

  defp add_equipment(_team, _activity, [], [], _user, _now), do: {:ok, []}

  defp add_equipment(team, activity, lines, tags, user, now),
    do: ChangeActivityEquipment.add(team, activity, lines, tags, user, now)

  # The flash for the equipment `rows` and the invites, as {kind, text}. Nothing for a
  # template that only fills in fields.
  defp invite(_team, _activity, [], _user, _now, []), do: {:info, nil}

  defp invite(_team, _activity, [], _user, _now, rows),
    do: {ActivityEquipmentLive.flash_kind(rows), ActivityEquipmentLive.result_text(rows, "added")}

  defp invite(team, activity, groups, user, now, rows) do
    picks = InviteMembers.group_picks(team, groups, now)

    {kind, text} =
      case InviteMembers.call(team, activity, picks, user, :template, now) do
        {:ok, result} ->
          day = Service.Format.month_day(activity.started_at, team.timezone)
          {ActivityEquipmentLive.flash_kind(rows ++ result.rows), invite_text(result, day)}

        # A template still logs equipment after an activity, but adds nobody.
        {:error, :started} ->
          {ActivityEquipmentLive.flash_kind(rows),
           "Its groups were left out: the activity has started."}

        {:error, reason} ->
          {:error, InviteMembers.error_text(team, reason)}
      end

    if rows == [],
      do: {kind, text},
      else: {kind, "#{ActivityEquipmentLive.result_text(rows, "added")} #{text}"}
  end

  defp count_items(n), do: Service.Format.count(n, one: "%d item", many: "%d items")
  defp count_tags(n), do: Service.Format.count(n, one: "%d tag", many: "%d tags")
  defp count_groups(n), do: Service.Format.count(n, one: "%d group", many: "%d groups")
  defp count_fields(n), do: Service.Format.count(n, one: "%d field", many: "%d fields")
end
