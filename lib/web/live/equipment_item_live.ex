defmodule Web.EquipmentItemLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Repo
  alias App.ViewData.EquipmentList

  @doc "SAR Duty Records has no equipment, so its teams have no equipment pages."
  def require_equipment!(team) do
    if D4H.records?(team), do: raise(Web.Status.NotFound)
  end

  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    require_equipment!(team)
    item = team |> EquipmentItem.find!(id) |> Repo.preload(:member)
    items = EquipmentItem.get_all(team.id)
    row = items |> EquipmentList.rows() |> Enum.find(&(&1.item.id == item.id))

    socket =
      assign(socket,
        page_title: item.title,
        item: item,
        row: row,
        contents: Enum.filter(items, &(&1.d4h_container_id == item.d4h_equipment_id)),
        usages: EquipmentUsage.for_item(item),
        kits: kits_with(item)
      )

    {:ok, socket}
  end

  defp kits_with(item) do
    App.Model.Kit
    |> join(:inner, [k], ki in assoc(k, :kit_items))
    |> where([k, ki], k.team_id == ^item.team_id and ki.equipment_item_id == ^item.id)
    |> order_by([k], asc: k.title)
    |> Repo.all()
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
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
            <dt>Type</dt>
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
          <div :if={@kits != []}>
            <dt>Kits</dt>
            <dd>
              <ul>
                <li :for={kit <- @kits}>
                  <.a navigate={~p"/teams/#{@current_team}/equipment/kits/#{kit.id}"}>
                    {kit.title}
                  </.a>
                </li>
              </ul>
            </dd>
          </div>
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

        <section id="item-activities">
          <h2 class="heading">Activities · {length(@usages)}</h2>
          <.table :if={@usages != []} id="item-usages" rows={@usages} class="table-striped">
            <:col :let={usage} label="Activity">
              <.a navigate={~p"/teams/#{@current_team}/activities/#{usage.activity.id}"}>
                {usage.activity.title}
              </.a>
            </:col>
            <:col :let={usage} label="Date" align="right" class="w-px whitespace-nowrap">
              {Service.Format.date_short(usage.activity.started_at, @current_team.timezone)}
            </:col>
            <:col :let={usage} label="Used" align="right" class="w-px whitespace-nowrap">
              {Web.ActivityEquipmentLive.amount(usage)}
            </:col>
          </.table>
          <p :if={@usages == []} class="hint">D4H has no activities with this item.</p>
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
