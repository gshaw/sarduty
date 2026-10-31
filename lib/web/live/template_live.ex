defmodule Web.TemplateLive do
  use Web, :live_view_app_layout

  import Web.Components.CustomFields, only: [custom_fields_table: 1]

  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.GroupMember
  alias App.Model.Template
  alias App.Operation.SaveTemplate
  alias App.ViewModel.ActivityFormViewModel

  # A template's page (#307): what it adds to an activity, all on one page, laid out like
  # the activity: the activity details beside Kind (#746), the description first, tags
  # under it, and Change template and Change tags in Actions. Items, groups, and fields
  # each have their Change link at their foot. Delete opens the confirm dialog here, with
  # no page (#714).
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    template = Template.find!(team, id)

    fields =
      if template.activity_kind,
        do: CustomField.get_all(team.id, template.activity_kind),
        else: []

    socket =
      assign(socket,
        page_title: template.title,
        template: template,
        tagged: %{tags: template |> Template.tags() |> Enum.map(& &1.title)},
        hours_tags: Activity.hours_tags(team),
        member_counts: GroupMember.counts(team.id),
        fields?: fields != [],
        items: Enum.sort_by(template.template_items, &String.downcase(&1.equipment_item.title)),
        field_rows:
          CustomField.rows(fields, template.custom_values, team.timezone, restricted: true)
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Templates" path={~p"/teams/#{@current_team}/templates"} />
      <:item label={@template.title} />
    </.breadcrumbs>
    <h1 class="title">{@template.title}</h1>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl id="template-details">
          <dt>Kind</dt>
          <dd>{Template.kind_label(@template) || "Any kind"}</dd>
          <div :if={@template.activity_title}>
            <dt>Title</dt>
            <dd>{@template.activity_title}</dd>
          </div>
          <div :if={@template.start_time}>
            <dt>Start time</dt>
            <dd>{Service.Format.time_short(@template.start_time)}</dd>
          </div>
          <div :if={@template.duration_minutes}>
            <dt>Duration</dt>
            <dd>{Service.Format.duration(@template.duration_minutes)}</dd>
          </div>
          <div :if={@template.place}>
            <dt>Address</dt>
            <dd>{@template.place}</dd>
          </div>
          <dt>Tax credit hours</dt>
          <dd>{hours_label(@template)}</dd>
        </dl>
        <dl>
          <dt>Actions</dt>
          <dd>
            <ul id="template-actions" class="action-list">
              <li>
                <.a
                  id="template-add-activity"
                  navigate={~p"/teams/#{@current_team}/activities/new?template=#{@template.id}"}
                >Add activity from this template</.a>
              </li>
              <li>
                <.a
                  id="template-edit"
                  navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/edit"}
                >Change template</.a>
              </li>
              <li>
                <.a
                  id="template-edit-tags"
                  navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/tags/edit"}
                >Change tags</.a>
              </li>
              <li>
                <.a
                  id="template-delete"
                  href="#"
                  phx-click="delete"
                  phx-disable-with="Deleting…"
                  {Web.DeleteConfirm.template(@template)}
                >Delete template</.a>
              </li>
            </ul>
          </dd>
        </dl>
      </aside>
      <main class="content-2/3">
        <section :if={@template.description} id="template-description" class="mb-8">
          <h2 class="heading">Description</h2>
          <.markdown content={@template.description} />
        </section>

        <.activity_tags
          id="template-tags"
          activity={@tagged}
          hours_tags={@hours_tags}
          class="mb-4"
        />

        <section id="template-items">
          <h2 class="heading">Items · {length(@items)}</h2>
          <.items_table
            :if={@items != []}
            id="template-items-table"
            items={@items}
            team={@current_team}
          />
          <p :if={@items == []} class="hint">No items.</p>
          <p class="action">
            <.a
              id="template-edit-items"
              navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/items/edit"}
            >{if @items == [], do: "Add items", else: "Change items"}</.a>
          </p>
        </section>

        <section id="template-groups" class="mt-8">
          <h2 class="heading">Groups · {length(@template.template_groups)}</h2>
          <.groups_table
            :if={@template.template_groups != []}
            id="template-groups-table"
            groups={Template.groups(@template)}
            member_counts={@member_counts}
            team={@current_team}
          />
          <p :if={@template.template_groups == []} class="hint">No groups.</p>
          <p class="action">
            <.a
              id="template-edit-groups"
              navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/groups/edit"}
            >{if @template.template_groups == [], do: "Add groups", else: "Change groups"}</.a>
          </p>
        </section>

        <section class="mt-8">
          <h2 class="heading">Fields · {length(@field_rows)}</h2>
          <%= cond do %>
            <% @fields? -> %>
              <.custom_fields_table id="template-fields" rows={@field_rows} />
              <p class="action">
                <.a
                  id="template-edit-fields"
                  navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/fields/edit"}
                >{if @field_rows == [], do: "Add fields", else: "Change fields"}</.a>
              </p>
            <% @template.activity_kind -> %>
              <p id="template-no-fields" class="hint">
                {Template.kind_label(@template)} activities have no custom fields.
              </p>
            <% true -> %>
              <p id="template-no-fields" class="hint">
                Fields go on a template for one kind of activity.
                <.a navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/edit"}>Change template</.a>
                to pick one.
              </p>
          <% end %>
        </section>
      </main>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :items, :list, required: true, doc: "template items, with their equipment items"
  attr :team, :map, required: true
  attr :link, :boolean, default: true, doc: "false on a form, which a link would leave"

  @doc "A template's items and their hours. Shared with Add activity (#747)."
  def items_table(assigns) do
    ~H"""
    <.table id={@id} rows={@items} row_id={&"item-#{&1.id}"} class="table-striped">
      <:col :let={line} label="Item">
        <.item_cell item={line.equipment_item} team={@team} link={@link} />
      </:col>
      <:col :let={line} label="Hours" align="right" class="w-px whitespace-nowrap">
        <.hours_cell :if={EquipmentItem.takes_hours?(line.equipment_item)} minutes={line.minutes} />
        <span :if={!EquipmentItem.takes_hours?(line.equipment_item)} class="text-text-muted">
          Not counted
        </span>
      </:col>
    </.table>
    """
  end

  attr :id, :string, required: true
  attr :groups, :list, required: true
  attr :member_counts, :map, required: true, doc: "from GroupMember.counts/1"
  attr :team, :map, required: true
  attr :link, :boolean, default: true, doc: "false on a form, which a link would leave"

  @doc "A template's groups and how many members each has. Shared with Add activity (#747)."
  def groups_table(assigns) do
    ~H"""
    <.table id={@id} rows={@groups} row_id={&"group-#{&1.id}"} class="table-striped">
      <:col :let={group} label="Group">
        <.group_cell group={group} team={@team} link={@link} />
      </:col>
      <:col :let={group} label="Members" class="w-px whitespace-nowrap" align="right">
        <span id={"group-#{group.id}-members"}>{Map.get(@member_counts, group.id, 0)}</span>
      </:col>
    </.table>
    """
  end

  defp hours_label(template),
    do:
      Enum.find_value(ActivityFormViewModel.hours(), fn {label, value} ->
        value == template.hours && label
      end)

  def handle_event("delete", _params, socket) do
    %{current_team: team, template: template} = socket.assigns
    :ok = SaveTemplate.delete(team, template)

    socket =
      socket
      |> put_flash(:info, "Deleted the #{template.title} template.")
      |> push_navigate(to: ~p"/teams/#{team}/templates")

    {:noreply, socket}
  end
end
