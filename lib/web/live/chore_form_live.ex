defmodule Web.ChoreFormLive do
  use Web,
      {:live_view_app_layout,
       access: :team,
       view_events: ["validate", "date", "add-person", "remove-person"],
       member_events: ["save", "delete"]}

  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.Member
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Operation.SaveChore
  alias Service.Format
  alias Web.ChoreCollectionLive

  # A chore's form (#341, #645), for everyone on the team, as Chores is.
  # /teams/:subdomain/chores/new: anyone who is a member logs a chore, for themselves and
  # anyone else who did it (#1102). Each person listed under Who did it gets their own
  # chore. A member stays on the list; a team admin can take themselves off, and can open
  # it from a member's Chores tab with `?member=`, starting with that member alone.
  # /teams/:subdomain/chores/:id/edit: a team admin changes any chore, any field, any date
  # that has passed, waiting or decided; its status stays and saving sends its activity
  # to D4H. A member changes their own chore only while it waits, or deletes it.
  # `mode` is `:team_admin` or `:own`, decided once here from who opened the page.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    if !Team.chores?(team), do: raise(Web.Status.NotFound)
    today = Service.Period.today(DateTime.utc_now(), team.timezone)
    {mode, chore} = mode_and_chore(socket.assigns, params["id"])
    chore = chore && %{chore | time: Service.Convert.duration_text(chore.minutes)}
    categories = categories(team.id, chore)
    data = chore || new_chore(today, nil)

    socket
    |> assign(mode: mode, chore: chore, today: today, params: %{})
    |> assign(page_title: if(chore, do: "Change chore", else: "Log a chore"))
    |> assign(categories: categories)
    |> assign_people(params)
    |> assign_form(Chore.build_changeset(data, %{}, [], nil))
    |> then(&{:ok, &1})
  end

  # Who did it, on a new chore: the reader, or with a team admin's `?member=` that member
  # alone, when the picker offers them.
  defp assign_people(%{assigns: %{chore: nil}} = socket, params) do
    %{current_team: team, current_member: me, team_admin?: team_admin?} = socket.assigns
    offered = offered(team, DateTime.utc_now())
    from = if team_admin?, do: Enum.find(offered, &(Integer.to_string(&1.id) == params["member"]))

    socket
    |> assign(offered: offered, from_member: from, people_error: nil)
    |> assign_listed(if(from, do: [from], else: [me]))
  end

  defp assign_people(socket, _params),
    do: assign(socket, offered: [], from_member: nil, people: [], people_error: nil)

  # Who the picker offers: current members the team counts, as Add members does.
  defp offered(team, now) do
    retiring = Standing.retiring_ids(team)

    team.id
    |> Member.get_all()
    |> Enum.filter(&(Member.current?(&1, now) and Member.counted?(&1, retiring)))
  end

  defp assign_listed(socket, people) do
    listed = MapSet.new(people, & &1.id)

    assign(socket,
      people: people,
      member_options: for(m <- socket.assigns.offered, m.id not in listed, do: {m.name, m.id})
    )
  end

  defp others_listed?(%{people: people, current_member: me}),
    do: Enum.any?(people, &(&1.id != me.id))

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
      <.duration_input field={@form[:time]} minutes={@form[:minutes]} label="Time" />
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

    <div :if={@categories != []} class="measure">
      <.error_summary form={@form} />
      <.who_field
        :if={!@chore}
        people={@people}
        options={@member_options}
        error={@people_error}
        current_member={@current_member}
        current_team={@current_team}
        team_admin?={@team_admin?}
      />
      <.form for={@form} id="chore-form" phx-change="validate" phx-submit="save">
        <.category_field form={@form} categories={@categories} />
        <.input
          field={@form[:description]}
          type="textarea"
          rows="3"
          label={if others_listed?(assigns), do: "What they did", else: "What you did"}
        >
          A team admin reads this, and so does everyone who opens its activity.
        </.input>
        <.date_field form={@form} today={@today}>
          {if @team_admin? and !@chore,
            do: "Any date that has passed.",
            else: "In the last #{Format.days(Chore.window_days())}."}
        </.date_field>
        <.duration_input field={@form[:time]} minutes={@form[:minutes]} label="Time" />
        <.form_actions>
          <.button
            id="chore-save"
            variant={:success}
            disabled={@viewing_as != nil}
            phx-disable-with="Saving…"
          >
            {save_label(@chore, @people)}
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
          <.button id="chore-log-cancel" navigate={cancel_path(assigns)}>Cancel</.button>
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
    </div>
    """
  end

  defp save_label(nil, people) when length(people) > 1, do: "Log #{length(people)} chores"
  defp save_label(nil, _people), do: "Log chore"
  defp save_label(_chore, _people), do: "Save chore"

  attr :people, :list, required: true
  attr :options, :list, required: true
  attr :error, :string, default: nil
  attr :current_member, :map, required: true
  attr :current_team, :map, required: true
  attr :team_admin?, :boolean, required: true

  # Its own form, as on Add members: a pick lists the person at once. The picker drops
  # each person listed, so its options change and it starts again empty. Names aren't
  # links: leaving the page drops the list.
  defp who_field(assigns) do
    ~H"""
    <form id="who-form" phx-change="add-person" phx-submit="add-person">
      <.input
        type="combobox"
        name="member-id"
        id="chore_people"
        label="Who did it"
        value=""
        placeholder="Find a member"
        options={@options}
        errors={List.wrap(@error)}
      >
        Everyone listed gets their own chore, the same in every other way.
        <:below>
          <ul id="who-did-it" class="mt-2">
            <li
              :for={person <- @people}
              id={"person-#{person.id}"}
              class="flex items-center gap-2 py-1"
            >
              <.member_cell
                member={person}
                team={@current_team}
                link={false}
                you={person.id == @current_member.id}
                id={"person-#{person.id}-badge"}
              />
              <.button
                :if={@team_admin? or person.id != @current_member.id}
                id={"remove-person-#{person.id}"}
                type="button"
                size={:sm}
                phx-click="remove-person"
                phx-value-id={person.id}
              >
                Remove
              </.button>
            </li>
          </ul>
        </:below>
      </.input>
    </form>
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

  def handle_event("validate", %{"chore" => params}, socket),
    do: {:noreply, validate(socket, params)}

  # Today or Yesterday: the date box takes it, and the rest of the form stays as typed.
  def handle_event("date", %{"date" => date}, socket),
    do: {:noreply, validate(socket, Map.put(socket.assigns.params, "date", date))}

  def handle_event("add-person", %{"member-id" => ""}, socket), do: {:noreply, socket}

  # Ids come from the browser, so only someone the picker offers is added.
  def handle_event("add-person", %{"member-id" => id}, socket) do
    %{offered: offered, people: people} = socket.assigns

    case Enum.find(offered, &(Integer.to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      person ->
        people = people |> Enum.concat([person]) |> Enum.uniq_by(& &1.id)
        {:noreply, socket |> assign(people_error: nil) |> assign_listed(people)}
    end
  end

  # A member's own row has no Remove, and stays.
  def handle_event("remove-person", %{"id" => id}, socket) do
    %{people: people, current_member: me, team_admin?: team_admin?} = socket.assigns

    people =
      Enum.reject(
        people,
        &(Integer.to_string(&1.id) == id and (team_admin? or &1.id != me.id))
      )

    {:noreply, assign_listed(socket, people)}
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

  def handle_event("save", %{"chore" => params} = form, %{assigns: %{chore: nil}} = socket) do
    %{current_team: team, current_member: me, people: people, today: today} = socket.assigns
    who = if socket.assigns.team_admin?, do: :team_admin, else: :member

    case SaveChore.log(team, me, people, params, today, who) do
      {:ok, chores} ->
        {:noreply, logged_all(socket, chores, is_map_key(form, "another"))}

      {:error, :nobody} ->
        {:noreply, nobody(socket, params, who)}

      {:error, reason} ->
        {:noreply, not_logged(socket, reason)}
    end
  end

  def handle_event("save", %{"chore" => params}, socket) do
    %{current_member: member, chore: chore, today: today} = socket.assigns

    case SaveChore.change_own(member, chore, params, today) do
      {:ok, saved} ->
        {:noreply, socket |> put_flash(:info, "Saved #{saved.description}.") |> back()}

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

  defp logged_all(socket, chores, true = _another), do: start_another(socket, chores)

  defp logged_all(socket, chores, false) do
    socket
    |> put_flash(:info, "#{logged(chores)}.")
    |> push_navigate(to: saved_path(socket.assigns))
  end

  # A list a stale page or a crafted event sent; the form shows neither.
  defp not_logged(socket, :without_you),
    do: put_flash(socket, :error, "Add yourself to Who did it.")

  defp not_logged(socket, :not_listed),
    do: put_flash(socket, :error, "Remove anyone who is not a current member.")

  defp not_logged(socket, %Ecto.Changeset{} = changeset),
    do: socket |> assign(people_error: nil) |> assign_form(changeset)

  # "Logged Truck 2 wash" for one person, "Logged 3 chores" for several.
  defp logged([chore]), do: "Logged #{chore.description}"
  defp logged(chores), do: "Logged #{length(chores)} chores"

  # Saving with nobody listed: the form's own errors too, with Who did it first.
  defp nobody(socket, params, who) do
    %{form: form, categories: categories, today: today} = socket.assigns

    changeset =
      form.source.data
      |> Chore.build_changeset(params, Enum.map(categories, & &1.id), today, who)
      |> Map.put(:action, :insert)

    changeset = %{changeset | errors: [{:people, {"Add who did it", []}} | changeset.errors]}
    socket |> assign(people_error: "Add who did it", params: params) |> assign_form(changeset)
  end

  # Back to the member's Chores tab it opened from; else Waiting, which shows every chore
  # a team admin logs for others, or Yours.
  defp saved_path(%{from_member: %Member{} = member, current_team: team}),
    do: ~p"/teams/#{team}/members/#{member.id}/chores"

  defp saved_path(%{team_admin?: true, current_team: team} = assigns) do
    if others_listed?(assigns),
      do: ChoreCollectionLive.view_path(team, :waiting),
      else: ChoreCollectionLive.view_path(team, :yours)
  end

  defp saved_path(%{current_team: team}), do: ChoreCollectionLive.view_path(team, :yours)

  defp cancel_path(%{from_member: %Member{} = member, current_team: team}),
    do: ~p"/teams/#{team}/members/#{member.id}/chores"

  defp cancel_path(%{current_team: team}), do: ChoreCollectionLive.view_path(team, :yours)

  # Log and add another: the same page, empty but for the last chore's date and category,
  # and Who did it as it was.
  defp start_another(socket, [saved | _others] = chores) do
    changeset =
      saved.date |> new_chore(saved.chore_category_id) |> Chore.build_changeset(%{}, [], nil)

    socket
    |> put_flash(:info, "#{logged(chores)}. Add the next one.")
    |> assign(params: %{}, people_error: nil)
    |> assign_form(changeset)
  end

  # Starts from what the form opened with, so Today or Yesterday before any typing keeps
  # the category Log and add another carried over.
  defp validate(socket, params) do
    %{form: form, categories: categories, today: today, team_admin?: team_admin?} =
      socket.assigns

    who = if team_admin?, do: :team_admin, else: :member

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
