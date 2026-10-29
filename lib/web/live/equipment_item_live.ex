defmodule Web.EquipmentItemLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.CustomFields

  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Operation.SaveEquipmentItem
  alias App.Repo
  alias App.ViewData.EquipmentList

  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    item = team |> EquipmentItem.find!(id) |> Repo.preload(:member)
    items = EquipmentItem.get_all(team.id)
    row = items |> EquipmentList.rows() |> Enum.find(&(&1.item.id == item.id))

    tab = socket.assigns.live_action
    fields = CustomField.get_all(team.id, "equipment")

    socket =
      assign(socket,
        page_title: if(tab == :fields, do: "#{item.title} · Fields", else: item.title),
        tab: tab,
        item: item,
        row: row,
        contents: Enum.filter(items, &(&1.d4h_container_id == item.d4h_equipment_id)),
        usages: EquipmentUsage.for_item(item),
        templates: templates_with(item),
        fields?: fields != [],
        field_rows: CustomField.rows(fields, item.custom_values, team.timezone, restricted: true)
      )

    {:ok, socket}
  end

  # A D4H team deletes its equipment in D4H, so only a Records team's page offers it.
  def handle_event("delete", _params, socket) do
    %{current_team: team, current_user: user, item: item} = socket.assigns

    with true <- D4H.records?(team),
         :ok <- SaveEquipmentItem.delete(team, item, user, DateTime.utc_now()) do
      {:noreply,
       socket
       |> put_flash(:info, "Deleted #{item.title}.")
       |> push_navigate(to: ~p"/teams/#{team}/equipment")}
    else
      false -> {:noreply, socket}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp templates_with(item) do
    App.Model.Template
    |> join(:inner, [k], ki in assoc(k, :template_items))
    |> where([k, ki], k.team_id == ^item.team_id and ki.equipment_item_id == ^item.id)
    |> order_by([k], asc: k.title)
    |> Repo.all()
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Equipment" path={~p"/teams/#{@current_team}/equipment"} />
      <:item label={@item.title} />
    </.breadcrumbs>
    <h1 class="title">{@item.title}</h1>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl id="item-details">
          <dt>Status</dt>
          <dd>
            {String.capitalize(@item.status)}
          </dd>
          <dt>Where</dt>
          <dd>{where(@row)}</dd>
          <div :if={@item.kind}>
            <dt>Category</dt>
            <dd>{@item.kind}</dd>
          </div>
          <div :if={@item.barcode}>
            <dt>Barcode</dt>
            <dd>{@item.barcode}</dd>
          </div>
          <div :if={@item.serial}>
            <dt>Serial number</dt>
            <dd>{@item.serial}</dd>
          </div>
          <div :if={@item.expires_at}>
            <dt>Expires</dt>
            <dd>{Service.Format.date_long(@item.expires_at, @current_team.timezone)}</dd>
          </div>
          <div :if={@templates != []}>
            <dt>Templates</dt>
            <dd>
              <ul>
                <li :for={template <- @templates}>
                  <.a navigate={~p"/teams/#{@current_team}/templates/#{template.id}"}>{template.title}</.a>
                </li>
              </ul>
            </dd>
          </div>
        </dl>
        <dl>
          <dt>Actions</dt>
          <dd>
            <%!-- A team on SAR Duty Records has no D4H to open, so it changes items here. --%>
            <ul id="item-actions" class="action-list">
              <li :if={D4H.records?(@current_team)}>
                <.a id="item-edit" navigate={~p"/teams/#{@current_team}/equipment/#{@item.id}/edit"}>Change item</.a>
              </li>
              <li :if={D4H.records?(@current_team)}>
                <.a
                  id="item-delete"
                  href="#"
                  phx-click="delete"
                  phx-disable-with="Deleting…"
                  {Web.DeleteConfirm.item(@item)}
                >Delete item</.a>
              </li>
              <li :if={@fields?}>
                <.a
                  id="item-actions-change-fields"
                  navigate={~p"/teams/#{@current_team}/equipment/#{@item.id}/fields/edit"}
                >Change fields</.a>
              </li>
              <li :if={!D4H.records?(@current_team)}>
                <.a external={true} href={D4H.equipment_url(@current_team, @item)}>Open in {@service}</.a>
              </li>
            </ul>
          </dd>
        </dl>
      </aside>
      <main class="content-2/3">
        <section :if={@contents != []} id="item-contents" class="mb-8">
          <h2 class="heading">Inside it · {length(@contents)}</h2>
          <ul>
            <li :for={item <- @contents}>
              <.a navigate={~p"/teams/#{@current_team}/equipment/#{item.id}"}>{item.title}</.a>
            </li>
          </ul>
        </section>

        <%!-- Tabs only when the team has D4H equipment fields (#705): Activities alone isn't a choice. --%>
        <.tabs :if={@fields? or @tab == :fields} label="Item">
          <:tab
            navigate={~p"/teams/#{@current_team}/equipment/#{@item.id}"}
            current={@tab == :activities}
          >
            Activities
          </:tab>
          <:tab
            navigate={~p"/teams/#{@current_team}/equipment/#{@item.id}/fields"}
            current={@tab == :fields}
          >
            Fields
          </:tab>
        </.tabs>
        <.custom_fields_table :if={@tab == :fields} id="item-fields" rows={@field_rows} />
        <p :if={@tab == :fields and @fields?} class="action">
          <.a
            id="item-fields-change"
            navigate={~p"/teams/#{@current_team}/equipment/#{@item.id}/fields/edit"}
          >Change fields</.a>
        </p>

        <section :if={@tab == :activities} id="item-activities">
          <h2 class="heading">Activities · {length(@usages)}</h2>
          <.table :if={@usages != []} id="item-usages" rows={@usages} class="table-striped">
            <:col :let={usage} label="Activity">
              <.a navigate={~p"/teams/#{@current_team}/activities/#{usage.activity.id}"}>{usage.activity.title}</.a>
            </:col>
            <:col :let={usage} label="Date" align="right" class="w-px whitespace-nowrap">
              {Service.Format.date_short(usage.activity.started_at, @current_team.timezone)}
            </:col>
            <:col :let={usage} label="Used" align="right" class="w-px whitespace-nowrap">
              {Web.ActivityEquipmentLive.amount(usage)}
            </:col>
          </.table>
          <p :if={@usages == []} class="hint">No activities have this item.</p>
        </section>
      </main>
    </div>
    """
  end

  defp where(%{holder: nil, inside: "", place: place}), do: place
  defp where(%{holder: nil, inside: inside, place: place}), do: "#{place} › #{inside}"
  defp where(%{holder: holder, inside: ""}), do: "With #{holder}"
  defp where(%{holder: holder, inside: inside}), do: "With #{holder} › #{inside}"
end
