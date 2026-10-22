defmodule Web.MeChoreFormLive do
  use Web, {:live_view_app_layout, access: :member}

  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Operation.SaveChore

  # A member logs a chore, or changes one while it waits (#341):
  # /teams/:subdomain/me/chores/new and /me/chores/:id/edit.
  def mount(params, _session, socket) do
    member = socket.assigns.current_member
    today = Service.Period.today(DateTime.utc_now(), member.team.timezone)
    chore = if id = params["id"], do: Chore.find_for_member!(member, id)
    if chore && !Chore.member_can_change?(chore), do: raise(Web.Status.NotFound)

    socket
    |> assign(member: member, chore: chore, today: today)
    |> assign(page_title: if(chore, do: "Change chore", else: "Log a chore"))
    |> assign(categories: categories(member.team_id, chore))
    |> assign_form(Chore.build_changeset(chore || new_chore(today), %{}, [], nil))
    |> then(&{:ok, &1})
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

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Your membership" path={~p"/teams/#{@member.team}/me"} />
      <:item label="Chores" path={~p"/teams/#{@member.team}/me/chores"} />
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
        A team admin reads this, and so does everyone who opens the D4H event.
      </.input>
      <.form_actions>
        <.button id="chore-save" variant={:success}>
          {if @chore, do: "Save chore", else: "Log chore"}
        </.button>
        <.button navigate={~p"/teams/#{@member.team}/me/chores"}>Cancel</.button>
        <:trailing :if={@chore}>
          <.button
            id="chore-delete"
            type="button"
            variant={:danger}
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
    %{chore: chore, today: today, categories: categories} = socket.assigns

    changeset =
      (chore || %Chore{})
      |> Chore.build_changeset(params, Enum.map(categories, & &1.id), today)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"chore" => params}, socket) do
    %{member: member, chore: chore, today: today} = socket.assigns

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
        |> push_navigate(to: ~p"/teams/#{member.team}/me/chores")
        |> then(&{:noreply, &1})

      {:error, :decided} ->
        {:noreply, decided(socket)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("delete", _params, socket) do
    %{member: member, chore: chore} = socket.assigns

    case SaveChore.delete_own(member, chore) do
      :ok ->
        socket
        |> put_flash(:info, "Deleted #{chore.description}.")
        |> push_navigate(to: ~p"/teams/#{member.team}/me/chores")
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
    |> push_navigate(to: ~p"/teams/#{socket.assigns.member.team}/me/chores")
  end
end
