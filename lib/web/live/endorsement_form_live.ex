defmodule Web.EndorsementFormLive do
  use Web, :live_view_app_layout

  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification
  alias App.Model.Group
  alias App.Model.GroupEndorsement
  alias App.Model.Qualification
  alias App.Repo
  alias App.ViewData.EndorsementRows

  # Adding and changing an endorsement (#320): its name, the qualifications that earn it,
  # and the group rules that require it. Opened from a group's rule editor, a new one
  # joins that group's rule.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    endorsement = if id = params["id"], do: Endorsement.get!(team.id, id)
    group = if id = params["group_id"], do: Repo.get_by!(Group, id: id, team_id: team.id)

    socket =
      socket
      |> assign(endorsement: endorsement, group: group)
      |> assign(page_title: if(endorsement, do: endorsement.name, else: "Add endorsement"))
      |> assign(qualifications: Qualification.get_all(team.id))
      |> assign_details()
      |> assign_form(Endorsement.build_changeset(endorsement || %Endorsement{}))

    {:ok, socket}
  end

  def handle_event("validate", %{"endorsement" => params}, socket) do
    changeset =
      (socket.assigns.endorsement || %Endorsement{})
      |> Endorsement.build_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"endorsement" => params}, %{assigns: %{endorsement: nil}} = socket) do
    team = socket.assigns.current_team

    case Endorsement.insert(team, params) do
      {:ok, endorsement} ->
        if group = socket.assigns.group, do: GroupEndorsement.add!(group, endorsement)

        {:noreply,
         socket
         |> put_flash(:info, "Endorsement added. Add the qualifications that earn it.")
         |> push_navigate(to: ~p"/teams/#{team}/endorsements/#{endorsement.id}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("save", %{"endorsement" => params}, socket) do
    case Endorsement.rename(socket.assigns.endorsement, params) do
      {:ok, endorsement} ->
        {:noreply,
         socket
         |> assign(endorsement: endorsement, page_title: endorsement.name)
         |> assign_form(Endorsement.build_changeset(endorsement))
         |> put_flash(:info, "Name saved.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("add-qualification", %{"qualification-id" => ""}, socket),
    do: {:noreply, socket}

  # The qualification id comes from the browser, so it is looked up through the team.
  def handle_event("add-qualification", %{"qualification-id" => id}, socket) do
    qualification = Repo.get_by!(Qualification, id: id, team_id: socket.assigns.current_team.id)

    EndorsementQualification.insert!(
      socket.assigns.endorsement,
      qualification.d4h_qualification_id
    )

    {:noreply, reload(socket)}
  end

  def handle_event("remove-qualification", %{"id" => id}, socket) do
    socket.assigns.endorsement
    |> EndorsementQualification.find!(id)
    |> EndorsementQualification.delete!()

    {:noreply, reload(socket)}
  end

  def handle_event("delete", _params, socket) do
    team = socket.assigns.current_team
    Endorsement.delete!(socket.assigns.endorsement)

    {:noreply,
     socket
     |> put_flash(:info, "#{socket.assigns.endorsement.name} deleted.")
     |> push_navigate(to: ~p"/teams/#{team}/endorsements")}
  end

  defp reload(socket) do
    endorsement = Endorsement.get!(socket.assigns.current_team.id, socket.assigns.endorsement.id)
    socket |> assign(endorsement: endorsement) |> assign_details()
  end

  defp assign_details(%{assigns: %{endorsement: nil}} = socket),
    do: assign(socket, rows: [], options: [], groups: [])

  defp assign_details(socket) do
    %{endorsement: endorsement, qualifications: qualifications, current_team: team} =
      socket.assigns

    assign(socket,
      rows: qualification_rows(endorsement, qualifications),
      options: qualification_options(endorsement, qualifications),
      groups: team.id |> EndorsementRows.groups_by_endorsement() |> Map.get(endorsement.id, [])
    )
  end

  defp qualification_rows(endorsement, qualifications) do
    titles = Map.new(qualifications, &{&1.d4h_qualification_id, &1.title})

    endorsement.endorsement_qualifications
    |> Enum.map(fn eq ->
      %{id: eq.id, title: titles[eq.d4h_qualification_id], d4h_id: eq.d4h_qualification_id}
    end)
    |> Enum.sort_by(&(&1.title || ""))
  end

  defp qualification_options(endorsement, qualifications) do
    held = endorsement |> Endorsement.qualification_ids() |> MapSet.new()
    for q <- qualifications, not MapSet.member?(held, q.d4h_qualification_id), do: {q.title, q.id}
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "endorsement"))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Endorsements" path={~p"/teams/#{@current_team}/endorsements"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <div class="measure">
      <.form for={@form} id="endorsement-form" phx-change="validate" phx-submit="save">
        <.error_summary form={@form} />
        <.input field={@form[:name]} label="Name" maxlength="60">
          What cards and group rules call it, such as "First Aid (7 hours or higher)".
        </.input>
        <.form_actions>
          <.button variant={:success}>{if @endorsement, do: "Save name", else: "Add endorsement"}</.button>
        </.form_actions>
      </.form>

      <section :if={@endorsement} id="endorsement-qualifications" class="mt-8">
        <h2 class="heading">Earned by any of</h2>
        <p class="hint mb-4">
          A member with any one of these has the endorsement. A change here changes every group
          rule that requires it.
        </p>
        <.table :if={@rows != []} id="qualifications" rows={@rows} row_id={&"qualification-#{&1.id}"}>
          <:col :let={row} label="Qualification">
            <span :if={row.title}>{row.title}</span>
            <span :if={!row.title} class="text-danger-text">
              No longer in D4H ({row.d4h_id})
            </span>
          </:col>
          <:col :let={row} label="" align="right">
            <.button
              id={"remove-qualification-#{row.id}"}
              size={:sm}
              phx-click="remove-qualification"
              phx-value-id={row.id}
            >
              Remove
            </.button>
          </:col>
        </.table>
        <p :if={@rows == []} class="text-danger-text" id="no-qualifications">
          No qualifications yet. No member holds it until you add one.
        </p>

        <form id="add-qualification-form" phx-submit="add-qualification" class="mt-4">
          <.input
            type="select"
            name="qualification-id"
            id="qualification-id"
            label="Add a qualification"
            value=""
            prompt="Select a qualification"
            options={@options}
          />
          <.button>Add qualification</.button>
        </form>
      </section>

      <section :if={@endorsement} id="endorsement-groups" class="mt-8">
        <h2 class="heading">Group rules</h2>
        <p :if={@groups == []} class="hint">
          No group rule requires it. Add it from a group's page.
        </p>
        <ul :if={@groups != []}>
          <li :for={group <- @groups}>
            <.a navigate={~p"/teams/#{@current_team}/groups/#{group.id}"}>{group.title}</.a>
          </li>
        </ul>
        <p :if={@current_team.id_cards_enabled} class="hint mt-4" id="endorsement-on-card">
          {if @endorsement.on_card,
            do: "ID cards list it.",
            else: "ID cards do not list it. Select it on the endorsements page."}
        </p>
      </section>

      <div :if={@endorsement} class="mt-8">
        <.button
          id="endorsement-delete"
          variant={:danger}
          phx-click="delete"
          data-confirm={delete_confirmation(@endorsement, @groups)}
        >
          Delete endorsement
        </.button>
      </div>
    </div>
    """
  end

  defp delete_confirmation(endorsement, groups) do
    rules =
      groups |> length() |> Service.Format.count(one: "%d group rule", many: "%d group rules")

    "Delete #{endorsement.name}? It comes off #{rules} and ID cards."
  end
end
