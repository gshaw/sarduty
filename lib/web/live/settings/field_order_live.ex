defmodule Web.Settings.FieldOrderLive do
  use Web, :live_view_app_layout

  import Web.Components.DragList

  alias App.Model.CustomField
  alias App.Model.Team
  alias App.Operation.ReorderCustomFields
  alias App.Repo

  # Change order, /teams/:subdomain/settings/fields/order?kind=incident (#1056 step 4):
  # the team's own live fields of one kind, dragged or moved into a new order and saved
  # at once. ReorderCustomFields sends a row for each field that moved. The
  # organization's fields keep their own order.
  def mount(params, _session, socket) do
    team = Repo.preload(socket.assigns.current_team, :organization)
    if !Team.d4h_can?(team, :custom_fields), do: raise(Web.Status.NotFound)
    target = if params["kind"] in CustomField.targets(), do: params["kind"], else: "incident"

    socket =
      assign(socket,
        page_title: "Change order",
        target: target,
        fields: ReorderCustomFields.fields(team, target),
        organization_name: team.organization && team.organization.short_name
      )

    {:ok, socket}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        fields_path: ~p"/teams/#{assigns.current_team}/settings/fields?kind=#{assigns.target}"
      )

    ~H"""
    <.breadcrumbs>
      <:item label="Team settings" path={~p"/teams/#{@current_team}/settings"} />
      <:item label="Fields" path={@fields_path} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>
    <p class="lead measure">
      The order of your team's {kind_text(@target)} fields on {record_text(@target)}.
      <span :if={@organization_name}>{@organization_name}'s fields keep their own order.</span>
    </p>

    <.empty_state :if={@fields == []} id="no-order-fields" title="No fields to put in order">
      Your team has no {kind_text(@target)} fields of its own.
      <.a navigate={@fields_path}>Back to fields</.a>
    </.empty_state>

    <form :if={@fields != []} id="order-form" class="mt-6" phx-submit="save">
      <.drag_list
        :let={field}
        id="field-order-list"
        class="mb-6"
        rows={@fields}
        key={&to_string(&1.id)}
        label={& &1.title}
        event="reorder"
        moves
      >
        {field.title}
      </.drag_list>
      <.form_actions>
        <.button id="order-save" variant={:success} phx-disable-with="Saving…">
          Save order
        </.button>
        <.button id="order-cancel" navigate={@fields_path}>Cancel</.button>
      </.form_actions>
    </form>
    """
  end

  defp kind_text("equipment"), do: "equipment"
  defp kind_text(target), do: target

  defp record_text("incident"), do: "an incident"
  defp record_text("exercise"), do: "an exercise"
  defp record_text("event"), do: "an event"
  defp record_text("member"), do: "a member"
  defp record_text("equipment"), do: "an item"

  def handle_event("reorder", %{"keys" => keys}, socket) do
    case reorder(socket.assigns.fields, keys, &to_string(&1.id)) do
      {:ok, fields} -> {:noreply, assign(socket, :fields, fields)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("save", _params, socket) do
    %{current_team: team, current_user: user, target: target, fields: fields} = socket.assigns
    ids = Enum.map(fields, & &1.id)

    case ReorderCustomFields.call(team, user, target, ids, DateTime.utc_now()) do
      :ok ->
        socket
        |> put_flash(:info, "Saved the order of your #{kind_text(target)} fields.")
        |> push_navigate(to: ~p"/teams/#{team}/settings/fields?kind=#{target}")
        |> then(&{:noreply, &1})

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end
end
