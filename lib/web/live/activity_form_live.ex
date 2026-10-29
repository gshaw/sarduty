defmodule Web.ActivityFormLive do
  use Web, :live_view_app_layout

  import Web.Components.CustomFields, only: [missing_text: 1]

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.CustomField
  alias App.Operation.DeleteActivity
  alias App.Operation.SaveActivity
  alias App.ViewModel.ActivityFormViewModel
  alias Web.Components.PlaceBox

  # Adding and changing activities (docs/records.md, #585), and deleting one on its own
  # page, /delete (docs/urls.md). D4H cannot delete an activity, so only a Records team
  # deletes one here.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    activity = if id = params["id"], do: Activity.find!(team, id)
    ensure_open!(team, activity, socket.assigns.live_action)

    form = ActivityFormViewModel.from_activity(activity, team)

    socket =
      socket
      |> assign(page_title: page_title(activity, socket.assigns.live_action))
      |> assign(activity: activity, form_data: form, records?: D4H.records?(team))
      |> assign(params: %{})
      |> assign(fields: activity && fields(team, activity))
      |> assign(delete_confirm: activity && delete_confirm(team, activity))
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
      :if={@live_action != :delete}
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

    <section
      :if={@live_action == :edit && !@records?}
      id="activity-delete-elsewhere"
      class="mt-8 measure"
    >
      <h2 class="heading">Delete the activity</h2>
      <p>Delete it in {@service}. {@service} does not let SAR Duty delete activities.</p>
      <p>
        <.a external={true} href={D4H.activity_url(@current_team, @activity)}>Open in {@service}</.a>
      </p>
    </section>

    <section :if={@live_action == :delete} id="activity-delete" class="measure">
      <p>
        It leaves every list and letter. Take attendance stops taking scans for it.
      </p>
      <.button
        id="activity-delete-button"
        phx-disable-with="Deleting…"
        type="button"
        variant={:danger}
        phx-click="delete"
        {@delete_confirm}
      >
        Delete activity
      </.button>
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

  defp ensure_open!(team, activity, action) do
    if activity && activity.deleted_at, do: raise(Web.Status.NotFound)
    if action == :delete and !D4H.records?(team), do: raise(Web.Status.NotFound)
  end

  defp page_title(nil, :new), do: "Add activity"
  defp page_title(activity, :edit), do: "Change #{activity.title}"
  defp page_title(activity, :delete), do: "Delete #{activity.title}"

  defp breadcrumb(:new), do: "Add activity"
  defp breadcrumb(:edit), do: "Change"
  defp breadcrumb(:delete), do: "Delete"

  # An activity with attendance asks for the box ticked (#651).
  defp delete_confirm(team, activity) do
    case Attendance.attended_count(activity, DateTime.utc_now()) do
      0 ->
        %{
          "data-confirm" => "Delete #{activity.title}?",
          "data-confirm-button" => "Delete activity"
        }

      count ->
        members = Service.Format.count(count, one: "%d member", many: "%d members")

        %{
          "data-confirm" => "Delete the activity #{activity.title}?",
          "data-confirm-list" =>
            Jason.encode!([
              "Its attendance for #{members} stops counting.",
              "It leaves every list and letter."
            ]),
          "data-confirm-warning" => "#{D4H.service_name(team)} can't bring it back.",
          "data-confirm-check" => "I understand the attendance for #{members} is lost.",
          "data-confirm-button" => "Delete activity"
        }
    end
  end

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
