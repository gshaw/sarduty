defmodule Web.ActivityFormLive do
  use Web, :live_view_app_layout

  import Web.Components.ActivityMap

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Operation.DeleteActivity
  alias App.Operation.FindPlace
  alias App.Operation.SaveActivity
  alias App.ViewModel.ActivityFormViewModel
  alias Web.Components.ActivityMap

  # Adding and changing activities (docs/records.md, #585). D4H cannot delete an activity,
  # so only a Records team deletes one here.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    activity = if id = params["id"], do: Activity.find!(team, id)
    if activity && activity.deleted_at, do: raise(Web.Status.NotFound)
    form = ActivityFormViewModel.from_activity(activity, team)

    socket =
      socket
      |> assign(page_title: if(activity, do: "Change #{activity.title}", else: "Add activity"))
      |> assign(activity: activity, form_data: form, records?: D4H.records?(team))
      |> assign(params: %{}, past: [], places: [], place_session: FindPlace.new_session())
      |> assign(past_places: FindPlace.past_places(team, DateTime.utc_now()))
      |> assign(
        description_locked?: ActivityFormViewModel.description_locked?(activity),
        published_locked?: activity != nil and Activity.locked?(activity)
      )
      |> assign_form(ActivityFormViewModel.changeset(form))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        :if={@activity}
        label={@activity.title}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label={if @activity, do: "Change", else: "Add activity"} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form for={@form} id="activity-form" phx-change="validate" phx-submit="save" class="measure">
      <.error_summary form={@form} />
      <.warning_text :if={@published_locked?} id="activity-published-locked" class="mb-6">
        A published activity cannot be changed. Untick Published and save first.
      </.warning_text>
      <%!-- A disabled fieldset sends none of its fields. --%>
      <fieldset disabled={@published_locked?}>
        <.input
          :if={!@activity}
          field={@form[:kind]}
          type="select"
          label="Kind"
          options={ActivityFormViewModel.kinds()}
        />
        <.input field={@form[:title]} label="Title" />
        <%!-- Side by side only where a date and time fit in half the width. --%>
        <div class="grid md:grid-cols-2 gap-x-6">
          <.input field={@form[:starts_at]} type="datetime-local" label="Start" />
          <.input field={@form[:ends_at]} type="datetime-local" label="Finish" />
        </div>
        <.place_field
          form={@form}
          past={@past}
          places={@places}
          kind={@form[:kind].value}
          timezone={@current_team.timezone}
          bookmark_source={if @records?, do: "Saved place", else: "#{@service} bookmark"}
        />
        <.input
          field={@form[:hours]}
          type="select"
          label="Tax credit hours"
          options={ActivityFormViewModel.hours()}
        >
          Which hours the activity counts for on tax credit letters.
        </.input>
        <.input field={@form[:tracking_number]} label="Tracking number (optional)" />
        <div :if={@description_locked?} id="activity-description-locked" class="mb-6">
          <.label>Description</.label>
          <.hint>
            Change the description in {@service}. It has things this form cannot keep, such as a table or a picture.
          </.hint>
          <.markdown content={@activity.description} />
        </div>
        <.input
          :if={!@description_locked?}
          field={@form[:description]}
          type="rich_text"
          label="Description (optional)"
        />
      </fieldset>
      <.input field={@form[:published]} type="checkbox" label="Published">
        Attendance cannot be changed once the activity is published.
      </.input>
      <.form_actions>
        <.button variant={:success} phx-disable-with={if @activity, do: "Saving…", else: "Adding…"}>
          {if @activity, do: "Save activity", else: "Add activity"}
        </.button>
      </.form_actions>
    </.form>

    <section :if={@activity && !@records?} id="activity-delete-elsewhere" class="mt-8 measure">
      <h2 class="heading">Delete the activity</h2>
      <p>Delete it in {@service}. {@service} does not let SAR Duty delete activities.</p>
      <p>
        <.a external={true} href={D4H.activity_url(@current_team, @activity)}>Open {@service} activity</.a>
      </p>
    </section>

    <section :if={@activity && @records?} id="activity-delete" class="mt-8 measure">
      <h2 class="heading">Delete the activity</h2>
      <p>
        It leaves every list and letter. Take attendance stops taking scans for it.
      </p>
      <.button
        id="activity-delete-button"
        phx-disable-with="Deleting…"
        type="button"
        variant={:danger}
        phx-click="delete"
        data-confirm={"Delete #{@activity.title}? Its attendance stops counting."}
      >
        Delete activity
      </.button>
    </section>
    """
  end

  # The place: the address text, a list of places that match it (the team's own, then
  # Mapbox's), and the pin of the one picked or the latitude and longitude pasted (#610).
  attr :form, :any, required: true
  attr :past, :list, required: true
  attr :places, :list, required: true
  attr :kind, :string, required: true
  attr :timezone, :string, required: true
  # Where a named place's name comes from, and so where to change it (#614).
  attr :bookmark_source, :string, required: true

  defp place_field(assigns) do
    field = assigns.form[:place]
    pin = Coordinate.build(assigns.form[:coordinate].value)

    assigns =
      assign(assigns,
        field: field,
        errors: if(used_input?(field), do: Enum.map(field.errors, &translate_error/1), else: []),
        pin: pin,
        open?: assigns.past != [] or assigns.places != [],
        map: pin && place_map(pin, assigns.kind, field.value)
      )

    ~H"""
    <div class={["mb-6", @errors != [] && "field-error"]}>
      <.label for={@field.id}>Address (optional)</.label>
      <.hint>
        Pick a place your team has used, or type an address or a place name, like Victoria Park, Truro, and pick a match. Or paste a latitude and longitude.
      </.hint>
      <.error :for={msg <- @errors}>{msg}</.error>
      <%!-- On the box and its list, so the click that focuses the box keeps the list open. --%>
      <div
        class="place-field"
        phx-click-away={@open? && "close_places"}
        phx-window-keydown={@open? && "close_places"}
        phx-key="Escape"
      >
        <div class="place-input">
          <input
            type="text"
            name={@field.name}
            id={@field.id}
            value={@field.value}
            class={@errors != [] && "is-invalid"}
            autocomplete="off"
            placeholder=" "
            phx-debounce="300"
            phx-focus="show_past"
            aria-controls="activity-places"
            aria-expanded={to_string(@open?)}
          />
          <button
            type="button"
            id="activity-place-clear"
            class="place-clear"
            aria-label="Clear the address"
            phx-click={
              JS.dispatch("sarduty:clear",
                to: "##{@field.id}",
                detail: %{also: "##{@form[:coordinate].id}"}
              )
            }
          >
            <.icon name="x" />
          </button>
        </div>
        <ul
          :if={@open?}
          id="activity-places"
          class="place-list"
          aria-label="Places that match"
        >
          <li :for={{place, i} <- Enum.with_index(@past)}>
            <button type="button" id={"activity-past-#{i}"} phx-click="pick_past" phx-value-i={i}>
              <span class="place-name">{place.name || place.text}</span>
              <span :if={place.name} class="place-detail">
                {named_detail(place, @bookmark_source)}
              </span>
              <span :if={place.count > 0} class="place-detail">
                {Service.Format.count(place.count, one: "1 activity", many: "%d activities")}, last {Service.Format.date_long(
                  place.last_at,
                  @timezone
                )}
              </span>
            </button>
          </li>
          <li :for={{place, i} <- Enum.with_index(@places)}>
            <button
              type="button"
              id={"activity-place-#{i}"}
              phx-click="pick_place"
              phx-value-id={place.id}
              phx-disable-with="Placing the pin…"
            >
              <span class="place-name">{place.name}</span>
              <span :if={place.detail} class="place-detail">{place.detail}</span>
            </button>
          </li>
        </ul>
      </div>
      <input
        type="hidden"
        name={@form[:coordinate].name}
        id={@form[:coordinate].id}
        value={@form[:coordinate].value}
      />
      <div :if={@pin} id="activity-pin" class="mt-3">
        <.activity_map id="activity-pin-map" map={@map} label="Map of the place" />
        <p class="hint mt-2">
          Latitude and longitude {Service.Format.coordinate(@pin, 5)}.
          <.button
            id="activity-pin-remove"
            type="button"
            variant={:link}
            phx-click="remove_pin"
          >
            Remove pin
          </.button>
        </p>
      </div>
    </div>
    """
  end

  # A bookmark with no address fills the box with its name, so it isn't said twice.
  defp named_detail(%{text: name, name: name}, source), do: source
  defp named_detail(%{text: text}, source), do: "#{text} · #{source}"

  @kinds %{"incident" => :incident, "exercise" => :exercise, "event" => :event}

  # Close enough to see the spot among the roads and trails around it.
  defp place_map({lat, lng}, kind, place) do
    point = %{lat: lat, lng: lng, kind: Map.get(@kinds, kind, :event), recent: true, tip: place}
    ActivityMap.build([point], {640, 320}, max_zoom: 14.0)
  end

  def handle_event("validate", %{"form" => params} = event, socket) do
    socket = socket |> assign(params: params) |> validate(params)

    if event["_target"] == ["form", "place"],
      do: {:noreply, find_places(socket, params["place"])},
      else: {:noreply, socket}
  end

  # The team's own places, with no Mapbox call, so the usual ones are a tap away.
  def handle_event("show_past", _params, socket) do
    %{past_places: past_places, form: form} = socket.assigns
    {:noreply, assign(socket, past: FindPlace.match_past(past_places, form[:place].value))}
  end

  def handle_event("pick_past", %{"i" => i}, socket) do
    %{past: past, params: params} = socket.assigns

    case Integer.parse(i) do
      {i, ""} when i in 0..(length(past) - 1)//1 ->
        place = Enum.at(past, i)

        params =
          Map.merge(params, %{"place" => place.text, "coordinate" => place.coordinate || ""})

        socket = assign(socket, past: [], places: [], place_session: FindPlace.new_session())
        {:noreply, socket |> assign(params: params) |> validate(params)}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("pick_place", %{"id" => id}, socket) do
    %{params: params, place_session: session} = socket.assigns
    socket = assign(socket, past: [], places: [], place_session: FindPlace.new_session())

    case FindPlace.pick(id, session) do
      {:ok, %{place: place, coordinate: coordinate}} ->
        params =
          Map.merge(params, %{
            "place" => place,
            "coordinate" => Coordinate.to_string(coordinate, 5)
          })

        {:noreply, socket |> assign(params: params) |> validate(params)}

      :error ->
        {:noreply, put_flash(socket, :error, "Mapbox did not answer. Pick the place again.")}
    end
  end

  def handle_event("remove_pin", _params, socket) do
    params = Map.put(socket.assigns.params, "coordinate", "")

    # A pasted latitude and longitude is the pin, so it goes too.
    params =
      if Coordinate.parse(params["place"]), do: Map.put(params, "place", ""), else: params

    {:noreply, socket |> assign(params: params) |> validate(params)}
  end

  def handle_event("close_places", _params, socket),
    do: {:noreply, assign(socket, past: [], places: [])}

  def handle_event("save", %{"form" => params}, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns

    case SaveActivity.call(team, activity, params, user, DateTime.utc_now()) do
      {:ok, saved} -> {:noreply, saved(socket, saved, "Saved #{params["title"]}.")}
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  def handle_event("delete", _params, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns

    case DeleteActivity.call(team, activity, user, DateTime.utc_now()) do
      {:ok, _activity} ->
        socket =
          socket
          |> put_flash(:info, "Deleted #{activity.title}.")
          |> push_navigate(to: ~p"/teams/#{team}/activities")

        {:noreply, socket}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  def handle_async(:places, {:ok, places}, socket), do: {:noreply, assign(socket, places: places)}
  def handle_async(:places, {:exit, _reason}, socket), do: {:noreply, assign(socket, places: [])}

  # The activity's page, or the list when the copy hasn't caught up yet.
  defp saved(socket, activity, text) do
    team = socket.assigns.current_team

    path =
      if activity,
        do: ~p"/teams/#{team}/activities/#{activity.id}",
        else: ~p"/teams/#{team}/activities"

    socket |> put_flash(:info, text) |> push_navigate(to: path)
  end

  defp validate(socket, params) do
    changeset =
      socket.assigns.form_data
      |> ActivityFormViewModel.changeset(params)
      |> Map.put(:action, :validate)

    assign_form(socket, changeset)
  end

  # Places that match the text, unless it is a latitude and longitude: the team's own at
  # once, and Mapbox's from 3 characters. The latest search wins when one is still running.
  defp find_places(socket, text) do
    %{current_team: team, place_session: session, past_places: past_places} = socket.assigns

    cond do
      Coordinate.parse(text) ->
        socket |> cancel_async(:places) |> assign(past: [], places: [])

      short?(text) ->
        socket
        |> cancel_async(:places)
        |> assign(past: FindPlace.match_past(past_places, text), places: [])

      true ->
        socket
        |> assign(past: FindPlace.match_past(past_places, text))
        |> start_async(:places, fn -> FindPlace.suggest(team, text, session) end)
    end
  end

  defp short?(nil), do: true
  defp short?(text), do: text |> String.trim() |> String.length() < 3

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "form"))
end
