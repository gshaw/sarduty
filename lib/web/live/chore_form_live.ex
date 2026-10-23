defmodule Web.ChoreFormLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Chore
  alias App.Model.Team
  alias App.Operation.SaveChore
  alias Web.MeChoreFormLive

  # A team admin changes a chore (#341), /teams/:subdomain/chores/:id/edit: any field, any
  # date that has passed, waiting or decided. Its status stays. Saving sends its activity to D4H.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    if !Team.chores?(team), do: raise(Web.Status.NotFound)
    chore = Chore.find!(team, id)

    socket
    |> assign(page_title: "Change chore", chore: chore, service: D4H.service_name(team))
    |> assign(today: Service.Period.today(DateTime.utc_now(), team.timezone))
    |> assign(categories: MeChoreFormLive.categories(team.id, chore))
    |> assign_form(Chore.build_changeset(chore, %{}, [], nil))
    |> then(&{:ok, &1})
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "chore"))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Chores" path={~p"/teams/#{@current_team}/chores"} />
      <:item label={@chore.description} path={~p"/teams/#{@current_team}/chores/#{@chore.id}"} />
      <:item label="Change chore" />
    </.breadcrumbs>
    <h1 class="title">Change chore</h1>
    <p class="lead">{@chore.member.name}</p>

    <.form for={@form} id="chore-form" class="measure" phx-change="validate" phx-submit="save">
      <.error_summary form={@form} />
      <.input field={@form[:date]} type="date" label="Date" max={Date.to_iso8601(@today)} />
      <.input field={@form[:minutes]} type="number" label="Minutes" min="1" step="1" />
      <.input
        field={@form[:chore_category_id]}
        type="select"
        label="Category"
        options={Enum.map(@categories, &{&1.title, &1.id})}
      />
      <.input field={@form[:description]} label="What they did" />
      <.form_actions>
        <.button id="chore-save" variant={:success} phx-disable-with={"Sending to #{@service}…"}>
          Save chore
        </.button>
        <.button navigate={~p"/teams/#{@current_team}/chores/#{@chore.id}"}>Cancel</.button>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"chore" => params}, socket) do
    %{chore: chore, categories: categories, today: today} = socket.assigns

    changeset =
      chore
      |> Chore.build_changeset(params, Enum.map(categories, & &1.id), today, :team_admin)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"chore" => params}, socket) do
    %{current_team: team, chore: chore, today: today} = socket.assigns

    case SaveChore.change(team, chore, params, today) do
      {:ok, saved} ->
        {:noreply, Web.ChoreLive.send_and_return(socket, saved, "Saved #{saved.description}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end
end
