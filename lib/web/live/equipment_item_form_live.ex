defmodule Web.EquipmentItemFormLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.EquipmentItem
  alias App.Model.Member
  alias App.Operation.SaveEquipmentItem
  alias App.Repo
  alias App.ViewModel.EquipmentItemFormViewModel

  # Adding and changing equipment items of a team on SAR Duty Records (#271,
  # docs/records.md). A D4H team changes its equipment in D4H. Delete is on the item's
  # page, in Actions (docs/urls.md).
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    unless D4H.records?(team), do: raise(Web.Status.NotFound)

    item = if id = params["id"], do: team |> EquipmentItem.find!(id) |> Repo.preload(:member)
    form = EquipmentItemFormViewModel.from_item(item, team.timezone)
    now = DateTime.utc_now()
    members = team.id |> Member.get_all() |> Enum.filter(&Member.current?(&1, now))
    items = EquipmentItem.get_all(team.id)
    places = EquipmentItemFormViewModel.places(items, members, item)

    socket =
      socket
      |> assign(page_title: page_title(item, socket.assigns.live_action))
      |> assign(item: item, form_data: form, places: places)
      |> assign_form(EquipmentItemFormViewModel.changeset(form))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Equipment" path={~p"/teams/#{@current_team}/equipment"} />
      <:item
        :if={@item}
        label={@item.title}
        path={~p"/teams/#{@current_team}/equipment/#{@item.id}"}
      />
      <:item label={breadcrumb(@live_action)} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form
      for={@form}
      id="equipment-item-form"
      phx-change="validate"
      phx-submit="save"
      class="measure"
    >
      <.error_summary form={@form} />
      <.input field={@form[:title]} label="Name" />
      <div class="grid grid-cols-2 gap-x-6">
        <.input
          field={@form[:item_type]}
          type="select"
          label="Type"
          options={EquipmentItemFormViewModel.types()}
        >
          Activities take hours for equipment only.
        </.input>
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={EquipmentItemFormViewModel.statuses()}
        />
      </div>
      <.input field={@form[:place]} type="select" label="Where it is" options={@places} />
      <.input :if={@form[:place].value == "new"} field={@form[:new_place]} label="New place">
        Such as the hall or the yard.
      </.input>
      <div class="grid grid-cols-2 gap-x-6">
        <.input field={@form[:barcode]} label="Barcode (optional)" />
        <.input field={@form[:serial]} label="Serial number (optional)" />
      </div>
      <.input field={@form[:expires_on]} type="date" label="Expires (optional)" />
      <.form_actions>
        <.button variant={:success} phx-disable-with={if @item, do: "Saving…", else: "Adding…"}>
          {if @item, do: "Save item", else: "Add item"}
        </.button>
        <.button
          id="equipment-item-cancel"
          navigate={
            if @item,
              do: ~p"/teams/#{@current_team}/equipment/#{@item.id}",
              else: ~p"/teams/#{@current_team}/equipment"
          }
        >
          Cancel
        </.button>
      </.form_actions>
    </.form>
    """
  end

  defp page_title(nil, :new), do: "Add item"
  defp page_title(item, :edit), do: "Change #{item.title}"

  defp breadcrumb(:new), do: "Add item"
  defp breadcrumb(:edit), do: "Change"

  def handle_event("validate", %{"form" => params}, socket) do
    changeset =
      socket.assigns.form_data
      |> EquipmentItemFormViewModel.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    %{current_team: team, current_user: user, item: item} = socket.assigns

    case SaveEquipmentItem.call(team, item, params, user, DateTime.utc_now()) do
      {:ok, saved} ->
        path =
          if saved,
            do: ~p"/teams/#{team}/equipment/#{saved.id}",
            else: ~p"/teams/#{team}/equipment"

        {:noreply,
         socket |> put_flash(:info, "Saved #{params["title"]}.") |> push_navigate(to: path)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "form"))
end
