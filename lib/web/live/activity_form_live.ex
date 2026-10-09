defmodule Web.ActivityFormLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Operation.DeleteActivity
  alias App.Operation.SaveActivity
  alias App.ViewModel.ActivityFormViewModel

  # Adding and changing a hosted team's activities (docs/hosted-d4h.md). A D4H team
  # changes its activities in D4H, so it has no such page.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    unless D4H.hosted?(team), do: raise(Web.Status.NotFound)

    activity = if id = params["id"], do: Activity.find!(team, id)
    if activity && activity.deleted_at, do: raise(Web.Status.NotFound)
    form = ActivityFormViewModel.from_activity(activity, team.timezone)

    socket =
      socket
      |> assign(page_title: if(activity, do: "Change #{activity.title}", else: "Add activity"))
      |> assign(activity: activity, form_data: form)
      |> assign_form(ActivityFormViewModel.changeset(form))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        :if={@activity}
        label={@activity.title}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label={if @activity, do: "Change", else: "Add activity"} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form for={@form} id="activity-form" phx-change="validate" phx-submit="save" class="max-w-xl">
      <.error_summary form={@form} />
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
      <.input field={@form[:place]} label="Address (optional)">
        An address or a place name, like Victoria Park, Truro.
      </.input>
      <.input
        field={@form[:hours]}
        type="select"
        label="SARVAC hours"
        options={ActivityFormViewModel.hours()}
      >
        Which hours the activity counts for on tax credit letters.
      </.input>
      <.input field={@form[:tracking_number]} label="Tracking number (optional)" />
      <.input field={@form[:description]} type="textarea" rows="5" label="Description (optional)" />
      <.input field={@form[:published]} type="checkbox" label="Published">
        Attendance cannot be changed once the activity is published.
      </.input>
      <.form_actions>
        <.button variant={:success}>{if @activity, do: "Save activity", else: "Add activity"}</.button>
      </.form_actions>
    </.form>

    <section :if={@activity} id="activity-delete" class="mt-8 max-w-xl">
      <h2 class="heading">Delete the activity</h2>
      <p>
        It leaves every list and letter. Its attendance links stop taking scans.
      </p>
      <.button
        id="activity-delete-button"
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

  def handle_event("validate", %{"form" => params}, socket) do
    changeset =
      socket.assigns.form_data
      |> ActivityFormViewModel.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
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

  # The activity's page, or the list when the copy hasn't caught up yet.
  defp saved(socket, activity, text) do
    team = socket.assigns.current_team

    path =
      if activity,
        do: ~p"/teams/#{team}/activities/#{activity.id}",
        else: ~p"/teams/#{team}/activities"

    socket |> put_flash(:info, text) |> push_navigate(to: path)
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "form"))
end
