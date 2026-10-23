defmodule Web.ChoreFormLive do
  use Web, :live_view_app_layout

  alias App.Model.Chore
  alias App.Operation.SaveChore
  alias Web.MeChoreFormLive

  # A team admin changes a chore (#341), /teams/:subdomain/chores/:id/edit: any field, any
  # date, waiting or decided. Its status stays.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    if !team.member_logins, do: raise(Web.Status.NotFound)
    chore = Chore.find!(team, id)

    socket
    |> assign(page_title: "Change chore", chore: chore)
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
      <.input field={@form[:date]} type="date" label="Date" />
      <.input field={@form[:minutes]} type="number" label="Minutes" min="1" step="1" />
      <.input
        field={@form[:chore_category_id]}
        type="select"
        label="Category"
        options={Enum.map(@categories, &{&1.title, &1.id})}
      />
      <.input field={@form[:description]} label="What they did" />
      <.form_actions>
        <.button id="chore-save" variant={:success}>Save chore</.button>
        <.button navigate={~p"/teams/#{@current_team}/chores/#{@chore.id}"}>Cancel</.button>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"chore" => params}, socket) do
    %{chore: chore, categories: categories} = socket.assigns

    changeset =
      chore
      |> Chore.build_changeset(params, Enum.map(categories, & &1.id), nil)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"chore" => params}, socket) do
    %{current_team: team, chore: chore} = socket.assigns

    case SaveChore.change(team, chore, params) do
      {:ok, saved} ->
        socket
        |> put_flash(:info, "Saved #{saved.description}.")
        |> push_navigate(to: ~p"/teams/#{team}/chores/#{chore.id}")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end
end
