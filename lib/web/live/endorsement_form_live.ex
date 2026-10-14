defmodule Web.EndorsementFormLive do
  use Web, :live_view_app_layout

  alias App.Model.Endorsement
  alias App.Model.EndorsementInclude
  alias App.Model.EndorsementQualification
  alias App.Model.Group
  alias App.Model.GroupEndorsement
  alias App.Model.Qualification
  alias App.Repo
  alias App.ViewData.EndorsementRows
  alias App.Worker.PushPassUpdatesWorker

  # Adding and changing an endorsement (#320): its name, the qualifications that earn it,
  # the endorsements it includes (#326), and the group rules that require it. Opened from
  # a group's rule editor, a new one joins that group's rule.
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
        push_passes(socket)

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

  def handle_event("add-include", %{"endorsement-id" => ""}, socket), do: {:noreply, socket}

  # Looked up through the team, and refused when it would make a loop.
  def handle_event("add-include", %{"endorsement-id" => id}, socket) do
    %{endorsement: endorsement, current_team: team} = socket.assigns
    other = Endorsement.get!(team.id, id)
    includes = EndorsementInclude.included_ids_by_endorsement(team.id)

    if Endorsement.can_include?(endorsement.id, other.id, includes),
      do: EndorsementInclude.insert!(endorsement, other)

    {:noreply, reload(socket)}
  end

  def handle_event("remove-include", %{"endorsement-id" => id}, socket) do
    other = Endorsement.get!(socket.assigns.current_team.id, id)
    EndorsementInclude.delete!(socket.assigns.endorsement, other.id)
    {:noreply, reload(socket)}
  end

  def handle_event("delete", _params, socket) do
    team = socket.assigns.current_team
    Endorsement.delete!(socket.assigns.endorsement)
    push_passes(socket)

    {:noreply,
     socket
     |> put_flash(:info, "#{socket.assigns.endorsement.name} deleted.")
     |> push_navigate(to: ~p"/teams/#{team}/endorsements")}
  end

  # Every change here can change what ID cards list, so passes on phones get pushed. The
  # job skips passes that look the same.
  defp push_passes(%{assigns: %{current_team: %{id_cards_enabled: true} = team}}),
    do: %{team_id: team.id} |> PushPassUpdatesWorker.new() |> Oban.insert!()

  defp push_passes(_socket), do: :ok

  defp reload(socket) do
    push_passes(socket)
    endorsement = Endorsement.get!(socket.assigns.current_team.id, socket.assigns.endorsement.id)
    socket |> assign(endorsement: endorsement) |> assign_details()
  end

  defp assign_details(%{assigns: %{endorsement: nil}} = socket),
    do:
      assign(socket,
        rows: [],
        options: [],
        groups: [],
        include_rows: [],
        include_options: [],
        counts_toward: []
      )

  defp assign_details(socket) do
    %{endorsement: endorsement, qualifications: qualifications, current_team: team} =
      socket.assigns

    others = Endorsement.get_all(team.id)

    assign(socket,
      rows: qualification_rows(endorsement, qualifications),
      options: qualification_options(endorsement, qualifications),
      groups: team.id |> EndorsementRows.groups_by_endorsement() |> Map.get(endorsement.id, []),
      include_rows: include_rows(endorsement, others, qualifications),
      include_options: include_options(endorsement, others),
      counts_toward: Enum.filter(others, &(endorsement.id in &1.included_ids))
    )
  end

  # Each included endorsement with every qualification that earns it, for the muted line.
  defp include_rows(endorsement, others, qualifications) do
    titles = Map.new(qualifications, &{&1.d4h_qualification_id, &1.title})

    for other <- others, other.id in endorsement.included_ids do
      %{
        id: other.id,
        name: other.name,
        qualifications:
          other
          |> Endorsement.qualification_ids()
          |> Enum.map(&titles[&1])
          |> Enum.reject(&is_nil/1)
          |> Enum.sort()
      }
    end
  end

  defp include_options(endorsement, others) do
    includes = Map.new(others, &{&1.id, &1.included_ids})

    for other <- others,
        other.id not in endorsement.included_ids,
        Endorsement.can_include?(endorsement.id, other.id, includes),
        do: {other.name, other.id}
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
    held = endorsement |> Endorsement.own_qualification_ids() |> MapSet.new()
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
        <p :if={@rows == [] and @include_rows == []} class="text-danger-text" id="no-qualifications">
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

      <section :if={@endorsement} id="endorsement-includes" class="mt-8">
        <h2 class="heading">Also earned by</h2>
        <p class="hint mb-4">
          A member with any of these endorsements has this one too. Add the next level up, such
          as 70 hour first aid. Then each course is listed once.
        </p>
        <.table
          :if={@include_rows != []}
          id="includes"
          rows={@include_rows}
          row_id={&"include-#{&1.id}"}
        >
          <:col :let={row} label="Endorsement">
            <.a navigate={~p"/teams/#{@current_team}/endorsements/#{row.id}"}>{row.name}</.a>
            <div class="hint">{Enum.join(row.qualifications, ", ")}</div>
          </:col>
          <:col :let={row} label="" align="right">
            <.button
              id={"remove-include-#{row.id}"}
              size={:sm}
              phx-click="remove-include"
              phx-value-endorsement-id={row.id}
            >
              Remove
            </.button>
          </:col>
        </.table>

        <form
          :if={@include_options != []}
          id="add-include-form"
          phx-submit="add-include"
          class="mt-4"
        >
          <.input
            type="select"
            name="endorsement-id"
            id="include-endorsement-id"
            label="Add an endorsement"
            value=""
            prompt="Select an endorsement"
            options={@include_options}
          />
          <.button>Add endorsement</.button>
        </form>

        <p :if={@counts_toward != []} class="hint mt-4" id="endorsement-counts-toward">
          Counts toward <span phx-no-format><%= for {other, i} <- Enum.with_index(@counts_toward) do %><%= if i > 0 do %>, <% end %><.a navigate={~p"/teams/#{@current_team}/endorsements/#{other.id}"}>{other.name}</.a><% end %></span>.
        </p>
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
