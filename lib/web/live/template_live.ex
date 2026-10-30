defmodule Web.TemplateLive do
  use Web, :live_view_app_layout

  import Web.Components.CustomFields, only: [custom_fields_table: 1]

  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.Template
  alias App.Operation.SaveTemplate

  # A template's page (#307): what it adds to an activity, all on one page. Each part has
  # its own Change link at its foot; Actions keep the template itself, and Delete opens
  # the confirm dialog here, with no page (#714). Its hours tag shows as Tax credit hours,
  # as on the activity.
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
        # The tags as an activity holds them, so the hours tag reads as Tax credit hours.
        tagged: %{tags: template |> Template.tags() |> Enum.map(& &1.title)},
        hours_tags: Activity.hours_tags(team),
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
          <div :if={hours_type = activity_hours_type(@tagged, @hours_tags)}>
            <dt>Tax credit hours</dt>
            <dd>{hours_type}</dd>
          </div>
        </dl>
        <dl>
          <dt>Actions</dt>
          <dd>
            <ul id="template-actions" class="action-list">
              <li>
                <.a
                  id="template-edit"
                  navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/edit"}
                >Change template</.a>
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
        <section id="template-tags" class="mb-8">
          <.activity_tags activity={@tagged} hours_tags={@hours_tags} />
          <p class="action">
            <.a
              id="template-edit-tags"
              navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/tags/edit"}
            >{if @template.template_tags == [], do: "Add tags", else: "Change tags"}</.a>
          </p>
        </section>

        <section id="template-items">
          <h2 class="heading">Items · {length(@items)}</h2>
          <.table
            :if={@items != []}
            id="template-items-table"
            rows={@items}
            row_id={&"item-#{&1.id}"}
            class="table-striped"
          >
            <:col :let={line} label="Item">
              <.item_cell item={line.equipment_item} team={@current_team} />
            </:col>
            <:col :let={line} label="Hours" align="right" class="w-px whitespace-nowrap">
              <.hours_cell
                :if={EquipmentItem.takes_hours?(line.equipment_item)}
                minutes={line.minutes}
              />
              <span :if={!EquipmentItem.takes_hours?(line.equipment_item)} class="text-text-muted">
                Not counted
              </span>
            </:col>
          </.table>
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
          <.table
            :if={@template.template_groups != []}
            id="template-groups-table"
            rows={Template.groups(@template)}
            row_id={&"group-#{&1.id}"}
            class="table-striped"
          >
            <:col :let={group} label="Group">
              <.a navigate={~p"/teams/#{@current_team}/groups/#{group.id}"}>{group.title}</.a>
            </:col>
          </.table>
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
