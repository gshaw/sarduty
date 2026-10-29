defmodule Web.CustomFieldsFormLive do
  @moduledoc """
  A record's Change fields page (#705): an activity's, a member's, or an equipment item's
  D4H custom fields, reached from Change fields on its Fields tab. The live action names
  the kind. Saving sends the changed ones to D4H (App.Operation.SaveCustomFields) and goes
  back to the Fields tab. A published activity is locked, as on Change activity.
  """
  use Web, :live_view_app_layout

  import Web.Components.CustomFields

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.Member
  alias App.Operation.SaveCustomFields

  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    record = find!(team, socket.assigns.live_action, id)
    fields = SaveCustomFields.fields(team, record)

    socket =
      assign(socket,
        page_title: "Change fields for #{title(record)}",
        record: record,
        fields: fields,
        values: record.custom_values || %{},
        locked?: match?(%Activity{}, record) and Activity.locked?(record),
        missing: missing(team, record, fields)
      )

    {:ok, socket}
  end

  defp find!(team, :activity, id) do
    activity = Activity.find!(team, id)
    if activity.deleted_at, do: raise(Web.Status.NotFound)
    activity
  end

  defp find!(team, :member, id), do: Member.find!(team, id)
  defp find!(team, :equipment, id), do: EquipmentItem.find!(team, id)

  defp title(%Activity{title: title}), do: title
  defp title(%Member{name: name}), do: name
  defp title(%EquipmentItem{title: title}), do: title

  defp missing(team, %Activity{} = activity, fields),
    do: CustomField.missing_count(fields, activity, team.timezone)

  defp missing(_team, _record, _fields), do: nil

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label={section(@record)} path={section_path(@current_team, @record)} />
      <:item label={crumb(@record)} path={fields_path(@current_team, @record)} />
      <:item label="Change fields" />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <p :if={@fields == []} id="custom-fields-none" class="measure">
      {D4H.service_name(@current_team)} has no fields for this {kind_word(@record)}.
    </p>

    <.form
      :if={@fields != []}
      for={%{}}
      as={:fields}
      id="custom-fields-form"
      phx-change="validate"
      phx-submit="save"
      class="measure"
    >
      <.warning_text :if={@locked?} id="custom-fields-locked" class="mb-6">
        A published activity cannot be changed. {D4H.unpublish_text(@current_team)}
      </.warning_text>
      <p :if={@missing} id="custom-fields-missing-count" class="mb-6">
        {missing_text(@missing)}
      </p>
      <%!-- A disabled fieldset sends none of its fields. --%>
      <fieldset disabled={@locked?}>
        <.custom_field_inputs
          fields={@fields}
          values={@values}
          publish?={match?(%Activity{}, @record)}
        />
      </fieldset>
      <.form_actions :if={!@locked?}>
        <.button variant={:success} phx-disable-with="Saving…">Save fields</.button>
      </.form_actions>
    </.form>
    """
  end

  defp section(%Activity{}), do: "Activities"
  defp section(%Member{}), do: "Members"
  defp section(%EquipmentItem{}), do: "Equipment"

  defp crumb(%Activity{ref_id: ref_id, title: title}), do: ref_id || title
  defp crumb(record), do: title(record)

  defp kind_word(%Activity{activity_kind: kind}), do: kind
  defp kind_word(%Member{}), do: "member"
  defp kind_word(%EquipmentItem{}), do: "item"

  defp section_path(team, %Activity{}), do: ~p"/teams/#{team}/activities"
  defp section_path(team, %Member{}), do: ~p"/teams/#{team}/members"
  defp section_path(team, %EquipmentItem{}), do: ~p"/teams/#{team}/equipment"

  defp fields_path(team, %Activity{id: id}), do: ~p"/teams/#{team}/activities/#{id}/fields"
  defp fields_path(team, %Member{id: id}), do: ~p"/teams/#{team}/members/#{id}/fields"
  defp fields_path(team, %EquipmentItem{id: id}), do: ~p"/teams/#{team}/equipment/#{id}/fields"

  # Keeps what was typed when the page renders again, such as after D4H refuses.
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, values: Map.merge(socket.assigns.values, params["fields"] || %{}))}
  end

  def handle_event("save", params, socket) do
    %{current_team: team, current_user: user, record: record} = socket.assigns
    values = params["fields"] || %{}

    case SaveCustomFields.call(team, record, values, user, DateTime.utc_now()) do
      {:ok, _saved} ->
        socket =
          socket
          |> put_flash(:info, "Fields saved.")
          |> push_navigate(to: fields_path(team, record))

        {:noreply, socket}

      {:error, text} ->
        socket =
          socket
          |> assign(values: Map.merge(socket.assigns.values, values))
          |> put_flash(:error, text)

        {:noreply, socket}
    end
  end
end
