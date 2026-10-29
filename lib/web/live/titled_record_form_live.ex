defmodule Web.TitledRecordFormLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.Qualification
  alias App.Operation.SaveTitledRecord
  alias App.ViewModel.TitleFormViewModel

  # Adding and renaming qualifications and groups. Both are only a title, so /edit
  # renames. Delete is on the record's page, in Actions (docs/urls.md). Qualifications are
  # for a team on SAR Duty Records (docs/records.md); a D4H team changes them in D4H.
  # Groups are for every team (#546), except the organization's.
  @kinds %{
    new_qualification: :qualification,
    edit_qualification: :qualification,
    new_group: :group,
    edit_group: :group
  }

  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    kind = Map.fetch!(@kinds, socket.assigns.live_action)
    unless kind == :group or D4H.records?(team), do: raise(Web.Status.NotFound)

    record = if id = params["id"], do: find!(kind, team, id)
    if record && Map.get(record, :organization_owned), do: raise(Web.Status.NotFound)
    form = %TitleFormViewModel{title: record && record.title}

    socket =
      socket
      |> assign(kind: kind, record: record, form_data: form)
      |> assign(page_title: page_title(kind, record))
      |> assign_form(TitleFormViewModel.changeset(form, %{}, 200))

    {:ok, socket}
  end

  defp find!(:qualification, team, id), do: Qualification.find!(team, id)
  defp find!(:group, team, id), do: Group.find!(team, id)

  defp page_title(:qualification, nil), do: "Add qualification"
  defp page_title(:group, nil), do: "Add group"
  defp page_title(_kind, record), do: "Rename #{record.title}"

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label={list_label(@kind)} path={list_path(@current_team, @kind)} />
      <:item :if={@record} label={@record.title} path={record_path(@current_team, @kind, @record)} />
      <:item label={if @record, do: "Rename", else: @page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form
      for={@form}
      id="titled-record-form"
      phx-submit="save"
      class="measure"
    >
      <.error_summary form={@form} />
      <.input field={@form[:title]} label="Title" />
      <.form_actions>
        <.button variant={:success} phx-disable-with={if @record, do: "Saving…", else: "Adding…"}>
          {if @record, do: "Save #{@kind}", else: @page_title}
        </.button>
        <.button
          id="titled-record-cancel"
          navigate={
            if @record,
              do: record_path(@current_team, @kind, @record),
              else: list_path(@current_team, @kind)
          }
        >
          Cancel
        </.button>
      </.form_actions>
    </.form>
    """
  end

  defp list_label(:qualification), do: "Qualifications"
  defp list_label(:group), do: "Groups"

  defp list_path(team, :qualification), do: ~p"/teams/#{team}/qualifications"
  defp list_path(team, :group), do: ~p"/teams/#{team}/groups"

  defp record_path(team, :qualification, record),
    do: ~p"/teams/#{team}/qualifications/#{record.id}"

  defp record_path(team, :group, record), do: ~p"/teams/#{team}/groups/#{record.id}"

  def handle_event("save", %{"form" => params}, socket) do
    %{current_team: team, current_user: user, kind: kind, record: record} = socket.assigns

    case SaveTitledRecord.save(team, kind, record, params, user, DateTime.utc_now()) do
      {:ok, saved} ->
        path = if saved, do: record_path(team, kind, saved), else: list_path(team, kind)

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
