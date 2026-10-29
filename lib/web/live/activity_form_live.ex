defmodule Web.ActivityFormLive do
  use Web, :live_view_app_layout

  import Web.Components.CustomFields, only: [missing_text: 1]

  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Operation.SaveActivity
  alias App.ViewModel.ActivityFormViewModel
  alias Web.Components.PlaceBox

  # Adding and changing activities (docs/records.md, #585). Delete is on the activity's
  # page, in Actions (docs/urls.md).
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    activity = if id = params["id"], do: Activity.find!(team, id)
    if activity && activity.deleted_at, do: raise(Web.Status.NotFound)

    form = ActivityFormViewModel.from_activity(activity, team)

    socket =
      socket
      |> assign(page_title: page_title(activity, socket.assigns.live_action))
      |> assign(activity: activity, form_data: form)
      |> assign(params: %{})
      |> assign(fields: activity && fields(team, activity))
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
        label={@activity.ref_id}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label={breadcrumb(@live_action)} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form
      for={@form}
      id="activity-form"
      phx-change="validate"
      phx-submit="save"
      class="measure"
    >
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
        <.live_component
          module={PlaceBox}
          id="activity"
          team={@current_team}
          field={@form[:place]}
          coordinate={@form[:coordinate]}
          label="Address (optional)"
          kind={map_kind(@form[:kind].value)}
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
        <.button
          id="activity-cancel"
          navigate={
            if @activity,
              do: ~p"/teams/#{@current_team}/activities/#{@activity.id}",
              else: ~p"/teams/#{@current_team}/activities"
          }
        >
          Cancel
        </.button>
      </.form_actions>
    </.form>

    <section :if={@live_action == :edit && @fields} id="activity-fields" class="mt-8 measure">
      <h2 class="heading">Fields</h2>
      <p :if={@fields.missing} id="activity-fields-missing-count">
        {missing_text(@fields.missing)}
      </p>
      <p class="action">
        <.a
          id="activity-fields-change"
          navigate={~p"/teams/#{@current_team}/activities/#{@activity.id}/fields/edit"}
        >Change fields</.a>
      </p>
    </section>
    """
  end

  # Change activity's Fields section (#705): the kind's D4H custom fields are on their own
  # page, with the Fields tab's count over a draft incident's missing ones. Nil for an
  # activity with no fields.
  defp fields(team, activity) do
    case CustomField.get_all(team.id, activity.activity_kind) do
      [] -> nil
      fields -> %{missing: CustomField.missing_count(fields, activity, team.timezone)}
    end
  end

  defp page_title(nil, :new), do: "Add activity"
  defp page_title(activity, :edit), do: "Change #{activity.title}"

  defp breadcrumb(:new), do: "Add activity"
  defp breadcrumb(:edit), do: "Change"

  @kinds %{"incident" => :incident, "exercise" => :exercise, "event" => :event}

  # The pin's dot takes the kind's colour.
  defp map_kind(kind), do: Map.get(@kinds, kind, :event)

  def handle_event("validate", %{"form" => params} = event, socket) do
    socket = socket |> assign(params: params) |> validate(params)

    if event["_target"] == ["form", "place"], do: PlaceBox.typed("activity", params["place"])
    {:noreply, socket}
  end

  def handle_event("save", %{"form" => params}, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns

    case SaveActivity.call(team, activity, params, user, DateTime.utc_now()) do
      {:ok, saved} -> {:noreply, saved(socket, saved, "Saved #{params["title"]}.")}
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  # A place picked, or its pin removed (#610).
  def handle_info({PlaceBox, values}, socket) do
    params = Map.merge(socket.assigns.params, values)
    {:noreply, socket |> assign(params: params) |> validate(params)}
  end

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

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "form"))
end
