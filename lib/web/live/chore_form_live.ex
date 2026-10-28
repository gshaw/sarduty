defmodule Web.ChoreFormLive do
  use Web,
      {:live_view_app_layout,
       access: :team, view_events: ["validate"], member_events: ["save", "delete"]}

  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.Team
  alias App.Operation.SaveChore
  alias Web.ChoreCollectionLive

  # A chore's form (#341, #645), for everyone on the team, as Chores is.
  # /teams/:subdomain/chores/new: anyone who is a member logs their own chore.
  # /teams/:subdomain/chores/:id/edit: a team admin changes any chore, any field, any date
  # that has passed, waiting or decided; its status stays and saving sends its activity
  # to D4H. A member changes their own chore only while it waits, or deletes it.
  # `mode` is `:team_admin` or `:own`, decided once here from who opened the page.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    if !Team.chores?(team), do: raise(Web.Status.NotFound)
    today = Service.Period.today(DateTime.utc_now(), team.timezone)
    {mode, chore} = mode_and_chore(socket.assigns, params["id"])

    socket
    |> assign(mode: mode, chore: chore, today: today)
    |> assign(page_title: if(chore, do: "Change chore", else: "Log a chore"))
    |> assign(categories: categories(team.id, chore))
    |> assign_form(Chore.build_changeset(chore || new_chore(today), %{}, [], nil))
    |> then(&{:ok, &1})
  end

  defp mode_and_chore(%{live_action: :new, current_member: nil}, _id),
    do: raise(Web.Status.NotFound)

  defp mode_and_chore(%{live_action: :new}, _id), do: {:own, nil}

  defp mode_and_chore(%{team_admin?: true, current_team: team}, id),
    do: {:team_admin, Chore.find!(team, id)}

  defp mode_and_chore(%{current_member: member}, id), do: {:own, own_chore!(member, id)}

  defp own_chore!(nil, _id), do: raise(Web.Status.NotFound)

  defp own_chore!(member, id) do
    chore = Chore.find_for_member!(member, id)
    if !Chore.member_can_change?(chore), do: raise(Web.Status.NotFound)
    chore
  end

  defp new_chore(today), do: %Chore{date: today, minutes: 60}

  @doc "The categories to offer: the open ones, and the chore's own once archived."
  def categories(team_id, chore) do
    open = ChoreCategory.get_open(team_id)

    if chore && !Enum.any?(open, &(&1.id == chore.chore_category_id)),
      do: Enum.concat(open, [chore.chore_category]),
      else: open
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "chore"))

  def render(%{mode: :team_admin} = assigns) do
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
        <.button id="chore-save" variant={:success} phx-disable-with="Sending…">
          Save chore
        </.button>
        <.button navigate={~p"/teams/#{@current_team}/chores/#{@chore.id}"}>Cancel</.button>
      </.form_actions>
    </.form>
    """
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Chores" path={ChoreCollectionLive.view_path(@current_team, :yours)} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.empty_state :if={@categories == []} id="no-chore-categories" title="No chore categories yet">
      A team admin sets up chore categories before members can log chores.
    </.empty_state>

    <.form
      :if={@categories != []}
      for={@form}
      id="chore-form"
      class="measure"
      phx-change="validate"
      phx-submit="save"
    >
      <.error_summary form={@form} />
      <.input field={@form[:date]} type="date" label="Date" max={Date.to_iso8601(@today)}>
        In the last {Service.Format.days(Chore.window_days())}.
      </.input>
      <.input field={@form[:minutes]} type="number" label="Minutes" min="1" step="1" />
      <.input
        field={@form[:chore_category_id]}
        type="select"
        label="Category"
        prompt="Select a category"
        options={Enum.map(@categories, &{&1.title, &1.id})}
      />
      <.input field={@form[:description]} label="What you did">
        A team admin reads this, and so does everyone who opens its activity.
      </.input>
      <.form_actions>
        <.button
          id="chore-save"
          variant={:success}
          disabled={@viewing_as != nil}
          phx-disable-with="Saving…"
        >
          {if @chore, do: "Save chore", else: "Log chore"}
        </.button>
        <.button navigate={ChoreCollectionLive.view_path(@current_team, :yours)}>Cancel</.button>
        <:trailing :if={@chore}>
          <.button
            id="chore-delete"
            type="button"
            variant={:danger}
            disabled={@viewing_as != nil}
            phx-click="delete"
            data-confirm={"Delete #{@chore.description}?"}
          >
            Delete chore
          </.button>
        </:trailing>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"chore" => params}, socket) do
    %{chore: chore, categories: categories, today: today, mode: mode} = socket.assigns
    who = if mode == :team_admin, do: :team_admin, else: :member

    changeset =
      (chore || %Chore{})
      |> Chore.build_changeset(params, Enum.map(categories, & &1.id), today, who)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"chore" => params}, %{assigns: %{mode: :team_admin}} = socket) do
    %{current_team: team, chore: chore, today: today} = socket.assigns

    case SaveChore.change(team, chore, params, today) do
      {:ok, saved} ->
        {:noreply, Web.ChoreLive.send_and_return(socket, saved, "Saved #{saved.description}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("save", %{"chore" => params}, socket) do
    %{current_member: member, chore: chore, today: today} = socket.assigns

    result =
      if chore,
        do: SaveChore.change_own(member, chore, params, today),
        else: SaveChore.log(member, params, today)

    case result do
      {:ok, saved} ->
        socket
        |> put_flash(
          :info,
          if(chore, do: "Saved #{saved.description}.", else: "Logged #{saved.description}.")
        )
        |> back()
        |> then(&{:noreply, &1})

      {:error, :decided} ->
        {:noreply, decided(socket)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("delete", _params, %{assigns: %{mode: :own}} = socket) do
    %{current_member: member, chore: chore} = socket.assigns

    case SaveChore.delete_own(member, chore) do
      :ok ->
        socket
        |> put_flash(:info, "Deleted #{chore.description}.")
        |> back()
        |> then(&{:noreply, &1})

      {:error, :decided} ->
        {:noreply, decided(socket)}
    end
  end

  # A team admin decided the chore after this page opened.
  defp decided(socket) do
    socket
    |> put_flash(
      :error,
      "This chore cannot change. A team admin has decided it since you opened it."
    )
    |> back()
  end

  defp back(socket),
    do:
      push_navigate(socket,
        to: ChoreCollectionLive.view_path(socket.assigns.current_team, :yours)
      )
end
