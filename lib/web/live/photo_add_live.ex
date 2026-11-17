defmodule Web.PhotoAddLive do
  @moduledoc """
  Add photos from Photos, /teams/:subdomain/photos/new (#1033): which activity? It lists
  the ones the person may add to now, newest first (App.Operation.AddActivityPhotos
  .addable/3): for a member the exercises and events they attended, and for a team
  admin every one that has started. Picking one opens its Add photos page, which checks
  again. With none to pick, the page is not found, as nothing links to it.
  """
  use Web, {:live_view_narrow_layout, access: :team, view_events: ["pick"]}

  alias App.Operation.AddActivityPhotos
  alias Service.Format
  alias Web.Components.Reply
  alias Web.PhotoCollectionLive

  def mount(_params, _session, socket) do
    %{current_team: team, team_admin?: team_admin?} = socket.assigns
    now = DateTime.utc_now()
    who = %{team_admin?: team_admin?, member: Reply.replier(socket.assigns, now)}
    activities = AddActivityPhotos.addable(team, who, now)
    if activities == [], do: raise(Web.Status.NotFound)

    options =
      for activity <- activities,
          do:
            {"#{activity.title} · #{Format.date_short(activity.started_at, team.timezone)}",
             to_string(activity.id)}

    {:ok, assign(socket, page_title: "Add photos", options: options)}
  end

  @doc "Add photos, asking which activity."
  def path(team), do: ~p"/teams/#{team}/photos/new"

  # The id comes from the browser: only one the box listed opens its page.
  def handle_event("pick", %{"activity_id" => id}, socket) do
    if Enum.any?(socket.assigns.options, fn {_label, value} -> value == id end) do
      {:noreply,
       push_navigate(socket, to: Web.ActivityPhoto.add_path(socket.assigns.current_team, id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("pick", _params, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Photos" path={PhotoCollectionLive.path(@current_team)} />
      <:item label="Add photos" />
    </.breadcrumbs>
    <h1 class="title">Add photos</h1>

    <form id="photos-activity-form" phx-change="pick" phx-submit="pick">
      <.input
        type="combobox"
        id="photos-activity"
        name="activity_id"
        label="Activity"
        prompt="Select an activity"
        options={@options}
        value=""
      >
        {if @team_admin?,
          do: "Every exercise and event that has started.",
          else: "The exercises and events you attended."}
      </.input>
      <.form_actions>
        <.button id="photos-activity-cancel" navigate={PhotoCollectionLive.path(@current_team)}>
          Cancel
        </.button>
      </.form_actions>
    </form>
    """
  end
end
