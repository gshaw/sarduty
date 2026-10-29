defmodule Web.ChoreFormLive do
  use Web,
      {:live_view_app_layout,
       access: :team, view_events: ["validate", "date"], member_events: ["save", "delete"]}

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
    chore = chore && %{chore | time: Chore.time_text(chore.minutes)}
    categories = categories(team.id, chore)
    data = chore || new_chore(today, nil)

    socket
    |> assign(mode: mode, chore: chore, today: today, params: %{})
    |> assign(page_title: if(chore, do: "Change chore", else: "Log a chore"))
    |> assign(categories: categories)
    |> assign_form(Chore.build_changeset(data, %{}, [], nil))
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

  defp new_chore(date, category_id), do: %Chore{date: date, chore_category_id: category_id}

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
      <.category_field form={@form} categories={@categories} />
      <.input field={@form[:description]} type="textarea" rows="3" label="What they did" />
      <.date_field form={@form} today={@today} />
      <.time_field form={@form} />
      <.form_actions>
        <.button id="chore-save" variant={:success} phx-disable-with="Sending…">
          Save chore
        </.button>
        <.button id="chore-cancel" navigate={~p"/teams/#{@current_team}/chores/#{@chore.id}"}>Cancel</.button>
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
      <.category_field form={@form} categories={@categories} />
      <.input field={@form[:description]} type="textarea" rows="3" label="What you did">
        A team admin reads this, and so does everyone who opens its activity.
      </.input>
      <.date_field form={@form} today={@today}>
        In the last {Service.Format.days(Chore.window_days())}.
      </.date_field>
      <.time_field form={@form} />
      <.form_actions>
        <.button
          id="chore-save"
          variant={:success}
          disabled={@viewing_as != nil}
          phx-disable-with="Saving…"
        >
          {if @chore, do: "Save chore", else: "Log chore"}
        </.button>
        <.button
          :if={!@chore}
          id="chore-save-another"
          name="another"
          value="true"
          disabled={@viewing_as != nil}
          phx-disable-with="Saving…"
        >
          Log and add another
        </.button>
        <.button id="chore-log-cancel" navigate={ChoreCollectionLive.view_path(@current_team, :yours)}>Cancel</.button>
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

  attr :form, Phoenix.HTML.Form, required: true
  attr :categories, :list, required: true

  # A combobox, not radios: six categories with descriptions filled a phone's screen. The
  # list shows each description, and the picked one's shows under the box.
  defp category_field(assigns) do
    value = to_string(assigns.form[:chore_category_id].value)
    assigns = assign(assigns, picked: Enum.find(assigns.categories, &(to_string(&1.id) == value)))

    ~H"""
    <.input
      field={@form[:chore_category_id]}
      type="combobox"
      label="Category"
      placeholder="Select a category"
      keyboard={false}
      options={Enum.map(@categories, &[key: &1.title, value: &1.id, "data-hint": &1.description])}
    >
      <:below>
        <p :if={@picked && @picked.description} id="chore-category-hint" class="hint mt-1">
          {@picked.description}
        </p>
      </:below>
    </.input>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :today, Date, required: true
  slot :inner_block

  defp date_field(assigns) do
    ~H"""
    <div class="max-w-xs">
      <.input field={@form[:date]} type="date" label="Date" max={Date.to_iso8601(@today)}>
        {render_slot(@inner_block)}
        <:below>
          <div class="flex gap-2 mt-2">
            <.button
              :for={{label, date} <- [{"Today", @today}, {"Yesterday", Date.add(@today, -1)}]}
              id={"chore-date-#{String.downcase(label)}"}
              type="button"
              size={:sm}
              phx-click="date"
              phx-value-date={Date.to_iso8601(date)}
            >
              {label}
            </.button>
          </div>
        </:below>
      </.input>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  # What the box read, as it reads everywhere else, once it reads as a time.
  defp time_field(assigns) do
    %{source: changeset} = assigns.form
    minutes = Ecto.Changeset.get_field(changeset, :minutes)
    read = if minutes && !Keyword.has_key?(changeset.errors, :time), do: minutes
    assigns = assign(assigns, read: read)

    ~H"""
    <div class="max-w-xs">
      <.input field={@form[:time]} label="Time" autocomplete="off">
        Like 45m, 2h, or 2.5h.
        <:below>
          <p :if={@read} id="chore-time-read" class="hint mt-1">
            Reads as {Service.Format.duration(@read)}.
          </p>
        </:below>
      </.input>
    </div>
    """
  end

  def handle_event("validate", %{"chore" => params}, socket),
    do: {:noreply, validate(socket, params)}

  # Today or Yesterday: the date box takes it, and the rest of the form stays as typed.
  def handle_event("date", %{"date" => date}, socket),
    do: {:noreply, validate(socket, Map.put(socket.assigns.params, "date", date))}

  def handle_event("save", %{"chore" => params}, %{assigns: %{mode: :team_admin}} = socket) do
    %{current_team: team, chore: chore, today: today} = socket.assigns

    case SaveChore.change(team, chore, params, today) do
      {:ok, saved} ->
        {:noreply, Web.ChoreLive.send_and_return(socket, saved, "Saved #{saved.description}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("save", %{"chore" => params} = form, socket) do
    %{current_member: member, chore: chore, today: today} = socket.assigns

    case save_own(member, chore, params, today) do
      {:ok, saved} when is_nil(chore) and is_map_key(form, "another") ->
        {:noreply, start_another(socket, saved)}

      {:ok, saved} ->
        verb = if chore, do: "Saved", else: "Logged"
        {:noreply, socket |> put_flash(:info, "#{verb} #{saved.description}.") |> back()}

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

  defp save_own(member, nil, params, today), do: SaveChore.log(member, params, today)

  defp save_own(member, chore, params, today),
    do: SaveChore.change_own(member, chore, params, today)

  # Log and add another: the same page, empty but for the last chore's date and category.
  defp start_another(socket, saved) do
    changeset =
      saved.date |> new_chore(saved.chore_category_id) |> Chore.build_changeset(%{}, [], nil)

    socket
    |> put_flash(:info, "Logged #{saved.description}. Add the next one.")
    |> assign(params: %{})
    |> assign_form(changeset)
  end

  # Starts from what the form opened with, so Today or Yesterday before any typing keeps
  # the category Log and add another carried over.
  defp validate(socket, params) do
    %{form: form, categories: categories, today: today, mode: mode} = socket.assigns
    who = if mode == :team_admin, do: :team_admin, else: :member

    changeset =
      form.source.data
      |> Chore.build_changeset(params, Enum.map(categories, & &1.id), today, who)
      |> Map.put(:action, :validate)

    socket |> assign(params: params) |> assign_form(changeset)
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
