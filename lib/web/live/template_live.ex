defmodule Web.TemplateLive do
  use Web, :live_view_app_layout

  import Web.Components.CustomFields, only: [custom_fields: 1]

  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.Template
  alias App.Operation.SaveTemplate

  # A template's page (#307): what it adds to an activity. Its Actions change each part on
  # a page of its own, and Delete opens the confirm dialog here, with no page (#714).
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
                  id="template-edit-items"
                  navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/items/edit"}
                >Change items</.a>
              </li>
              <li>
                <.a
                  id="template-edit-tags"
                  navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/tags/edit"}
                >Change tags</.a>
              </li>
              <li>
                <.a
                  id="template-edit-groups"
                  navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/groups/edit"}
                >Change groups</.a>
              </li>
              <li :if={@fields?}>
                <.a
                  id="template-edit-fields"
                  navigate={~p"/teams/#{@current_team}/templates/#{@template.id}/fields/edit"}
                >Change fields</.a>
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
              <.a navigate={~p"/teams/#{@current_team}/equipment/#{line.equipment_item.id}"}>{line.equipment_item.title}</.a>
            </:col>
            <:col :let={line} label="Hours" class="w-px whitespace-nowrap">
              {hours(line)}
            </:col>
          </.table>
          <p :if={@items == []} class="hint">No items.</p>
        </section>

        <section id="template-tags" class="mt-8">
          <h2 class="heading">Tags · {length(@template.template_tags)}</h2>
          <ul :if={@template.template_tags != []} class="flex flex-wrap gap-2">
            <li :for={tag <- Template.tags(@template)}>
              <.badge kind={:outline}>{tag.title}</.badge>
            </li>
          </ul>
          <p :if={@template.template_tags == []} class="hint">No tags.</p>
        </section>

        <section id="template-groups" class="mt-8">
          <h2 class="heading">Groups · {length(@template.template_groups)}</h2>
          <ul :if={@template.template_groups != []}>
            <li :for={group <- Template.groups(@template)}>
              <.a navigate={~p"/teams/#{@current_team}/groups/#{group.id}"}>{group.title}</.a>
            </li>
          </ul>
          <p :if={@template.template_groups == []} class="hint">No groups.</p>
        </section>

        <.custom_fields
          id="template-fields"
          title={"Fields · #{length(@field_rows)}"}
          rows={@field_rows}
        />
      </main>
    </div>
    """
  end

  defp hours(%{equipment_item: item, minutes: minutes}) do
    if EquipmentItem.takes_hours?(item),
      do: Service.Format.duration(minutes),
      else: "Not counted"
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
