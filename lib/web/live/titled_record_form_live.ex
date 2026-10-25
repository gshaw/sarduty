defmodule Web.TitledRecordFormLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRule
  alias App.Model.Qualification
  alias App.Model.Template
  alias App.Operation.BuildGroupRulePreview
  alias App.Operation.SaveTitledRecord
  alias App.Repo
  alias App.ViewModel.TitleFormViewModel

  # Adding, renaming, and deleting qualifications and groups. Both are only a title.
  # Qualifications are for a team on SAR Duty Records (docs/records.md); a D4H team
  # changes them in D4H. Groups are for every team (#546), except the organization's.
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
      |> assign(:delete_text, record && delete_text(kind, team, record))
      |> assign(page_title: page_title(kind, record))
      |> assign_form(TitleFormViewModel.changeset(form, %{}, 200))

    {:ok, socket}
  end

  defp find!(:qualification, team, id), do: Qualification.find!(team, id)
  defp find!(:group, team, id), do: Group.find!(team, id)

  defp page_title(:qualification, nil), do: "Add qualification"
  defp page_title(:group, nil), do: "Add group"
  defp page_title(_kind, record), do: "Change #{record.title}"

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label={list_label(@kind)} path={list_path(@current_team, @kind)} />
      <:item :if={@record} label={@record.title} path={record_path(@current_team, @kind, @record)} />
      <:item label={if @record, do: "Change", else: @page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form for={@form} id="titled-record-form" phx-submit="save" class="measure">
      <.error_summary form={@form} />
      <.input field={@form[:title]} label="Title" />
      <.form_actions>
        <.button variant={:success} phx-disable-with={if @record, do: "Saving…", else: "Adding…"}>
          {if @record, do: "Save #{@kind}", else: @page_title}
        </.button>
      </.form_actions>
    </.form>

    <section :if={@record} id="record-delete" class="mt-8 measure">
      <h2 class="heading">Delete the {@kind}</h2>
      <p>{@delete_text}</p>
      <.button
        id="record-delete-button"
        phx-disable-with="Deleting…"
        type="button"
        variant={:danger}
        phx-click="delete"
        data-confirm={"Delete #{@record.title}? #{@delete_text}"}
      >
        Delete {@kind}
      </.button>
    </section>
    """
  end

  defp list_label(:qualification), do: "Qualifications"
  defp list_label(:group), do: "Groups"

  defp list_path(team, :qualification), do: ~p"/teams/#{team}/qualifications"
  defp list_path(team, :group), do: ~p"/teams/#{team}/groups"

  defp record_path(team, :qualification, record),
    do: ~p"/teams/#{team}/qualifications/#{record.id}"

  defp record_path(team, :group, record), do: ~p"/teams/#{team}/groups/#{record.id}"

  defp delete_text(:qualification, _team, _record), do: "Every member who holds it loses it."

  # What else stops: the groups whose rules name it, the templates that add its members,
  # and the attendance check.
  defp delete_text(:group, team, group) do
    count = GroupMember |> where(group_id: ^group.id) |> Repo.aggregate(:count)
    context = BuildGroupRulePreview.load(team)

    rules =
      context.rules
      |> GroupRule.used_by(group.d4h_group_id)
      |> Enum.map(&context.groups[&1])
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.title)
      |> Enum.sort()

    templates =
      Template
      |> join(:inner, [t], tg in assoc(t, :template_groups))
      |> where([t, tg], t.team_id == ^team.id and tg.group_id == ^group.id)
      |> order_by([t], asc: t.title)
      |> select([t], t.title)
      |> Repo.all()

    [
      if(count == 0,
        do: "Nobody is in it.",
        else:
          "Its #{Service.Format.count(count, one: "%d member leaves", many: "%d members leave")} it."
      ),
      if(rules != [],
        do: "The rules of #{Service.Format.and_list(rules)} stop working until you change them."
      ),
      templates_text(templates),
      if(team.watch_d4h_group_id == group.d4h_group_id,
        do: "The attendance check stops until you select another group."
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp templates_text([]), do: nil
  defp templates_text([one]), do: "The template #{one} stops adding its members."

  defp templates_text(templates),
    do: "The templates #{Service.Format.and_list(templates)} stop adding its members."

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

  def handle_event("delete", _params, socket) do
    %{current_team: team, current_user: user, kind: kind, record: record} = socket.assigns

    case SaveTitledRecord.delete(team, kind, record, user, DateTime.utc_now()) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Deleted #{record.title}.")
          |> push_navigate(to: list_path(team, kind))

        {:noreply, socket}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "form"))
end
