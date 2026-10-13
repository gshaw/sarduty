defmodule Web.ActivityTemplateLive do
  use Web, :live_view_app_layout

  import Web.ActivityEquipmentLive, only: [lines_table: 1]

  alias App.Adapter.D4H
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.Template
  alias App.Operation.ChangeActivityEquipment
  alias App.Operation.InviteGroups
  alias Web.ActivityEquipmentLive

  # Applying templates to an activity (#162). Each template adds its items, with hours to
  # check, its tags, and its groups to invite to one list. Sending writes the items and
  # tags to D4H as equipment usages and the activity's tags, then sends the invites.
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
        |> assign(lines: [], tags: [], groups: [])
        |> assign(templates: Template.get_all(team.id), service: D4H.service_name(team))

      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
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
            class="table-striped mb-4"
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
          <p class="hint">
            <.a navigate={~p"/teams/#{@current_team}/templates"}>
              {if @templates == [], do: "Add a template", else: "Change templates"}
            </.a>
            for items, tags, and groups that go together.
          </p>
        </section>
      </aside>

      <main class="content-2/3">
        <section id="template-to-add">
          <h2 class="heading">To add</h2>
          <.form
            :if={@lines != [] or @tags != [] or @groups != []}
            for={%{}}
            id="template-lines"
            phx-change="hours"
            phx-submit="send"
          >
            <.lines_table :if={@lines != []} id="template-lines-table" lines={@lines} km />
            <div :if={@tags != []} id="template-tags" class="mt-4">
              <h3 class="subheading">Tags</h3>
              <p class="hint mb-2">The activity keeps the tags it has.</p>
              <.tags_to_add id="template-tags-table" tags={@tags} />
            </div>
            <div :if={@groups != []} id="template-groups" class="mt-4">
              <h3 class="subheading">Invite</h3>
              <p class="hint mb-2">
                SAR Duty invites each member of these groups who is not on the activity. They answer in {@service}.
              </p>
              <.groups_to_invite id="template-groups-table" groups={@groups} />
            </div>
            <.form_actions>
              <.button id="template-send" variant={:success} phx-disable-with="Adding…">
                Add to activity
              </.button>
            </.form_actions>
          </.form>
          <p
            :if={@lines == [] and @tags == [] and @groups == []}
            id="template-nothing-to-add"
            class="hint"
          >
            Add one or more templates. Check the hours and a vehicle's km, then add them to the activity.
          </p>
        </section>
      </main>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :tags, :list, required: true

  @doc "Tags about to be added, each with a remove button. Shared with the template form."
  def tags_to_add(assigns) do
    ~H"""
    <.table id={@id} rows={@tags} row_id={&"tag-#{&1.id}"} class="table-striped mb-4">
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

  @doc "Groups about to be invited, each with a remove button. Shared with the template form."
  def groups_to_invite(assigns) do
    ~H"""
    <.table id={@id} rows={@groups} row_id={&"group-#{&1.id}"} class="table-striped mb-4">
      <:col :let={group} label="Group">{group.title}</:col>
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

  @doc ~s(What a template holds, as "3 items, 2 tags, 1 group".)
  def template_contents(template) do
    tags = length(template.template_tags)
    groups = length(template.template_groups)

    [count_items(length(template.template_items))]
    |> Kernel.++(if tags > 0, do: [count_tags(tags)], else: [])
    |> Kernel.++(if groups > 0, do: [count_groups(groups)], else: [])
    |> Enum.join(", ")
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

  def handle_event("add-template", %{"id" => id}, socket) do
    %{activity: activity, lines: lines, used: used} = socket.assigns
    template = Template.find!(socket.assigns.current_team, id)

    new =
      for line <- template.template_items, EquipmentItem.in_service?(line.equipment_item) do
        {line.equipment_item, line.minutes}
      end

    socket =
      assign(socket,
        lines: ActivityEquipmentLive.add_lines(lines, new, used),
        tags: add_tags(socket.assigns.tags, Template.tags(template), activity.tags),
        groups: add_groups(socket.assigns.groups, Template.groups(template))
      )

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

  def handle_event("send", params, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns

    lines =
      socket.assigns.lines
      |> ActivityEquipmentLive.put_typed(params)
      |> Enum.map(&ActivityEquipmentLive.to_add/1)

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

  defp reject_id(records, id), do: Enum.reject(records, &(Integer.to_string(&1.id) == id))

  defp add_equipment(_team, _activity, [], [], _user, _now), do: {:ok, []}

  defp add_equipment(team, activity, lines, tags, user, now),
    do: ChangeActivityEquipment.add(team, activity, lines, tags, user, now)

  # The flash for the equipment `rows` and the invites, as {kind, text}.
  defp invite(_team, _activity, [], _user, _now, rows),
    do: {ActivityEquipmentLive.flash_kind(rows), ActivityEquipmentLive.result_text(rows, "added")}

  defp invite(team, activity, groups, user, now, rows) do
    {kind, text} =
      case InviteGroups.call(team, activity, groups, user, now) do
        {:ok, invites} ->
          {ActivityEquipmentLive.flash_kind(rows ++ invites), invite_text(invites)}

        {:error, text} ->
          {:error, text}
      end

    if rows == [],
      do: {kind, text},
      else: {kind, "#{ActivityEquipmentLive.result_text(rows, "added")} #{text}"}
  end

  defp count_items(n), do: Service.Format.count(n, one: "%d item", many: "%d items")
  defp count_tags(n), do: Service.Format.count(n, one: "%d tag", many: "%d tags")
  defp count_groups(n), do: Service.Format.count(n, one: "%d group", many: "%d groups")
  defp count_members(n), do: Service.Format.count(n, one: "%d member", many: "%d members")
end
