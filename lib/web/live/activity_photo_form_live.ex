defmodule Web.ActivityPhotoFormLive do
  use Web,
      {:live_view_narrow_layout,
       access: :team, view_events: ["validate", "remove"], member_events: ["save"]}

  alias App.Model.Activity
  alias App.Model.ActivityPhotoAsk
  alias App.Operation.AddActivityPhotos
  alias Service.Format
  alias Web.ActivityLive
  alias Web.Components.Reply
  alias Web.Navigation
  alias Web.PhotoAskLinks

  # Add photos, /teams/:subdomain/activities/:id/photos/new (#1032): someone who was at
  # an exercise or an event adds their photos of it, with a phone in hand, so a narrow
  # page. It opens only for whoever may add now (AddActivityPhotos.may_add?/4): a member
  # who attended, or a team admin. Anyone else gets a 404.
  #
  # The email that asks everyone who attended for their photos (#1034) opens the same
  # page at /photos/activities/:token, with no login: the token names the ask, and so
  # the activity and the member. Nothing the session or the form says changes who. The
  # link works for 30 days, as often as they like. One too old, or whose member may no
  # longer add, says so. `team` is the page's team either way: `current_team` is only
  # set for someone logged in to it.
  #
  # The rules show above the files, every time. Take a photo opens the camera, and
  # Select photos the phone's photos, for many at once. Each photo uploads the moment it
  # is picked and is checked on arrival (Service.ActivityPhoto.check/1), so one SAR Duty
  # cannot read is refused at once, by name. No tools here: adding 20 stays quick.
  #
  # The send has one caption and one permission to post, a box that starts unchecked.
  # Add reads each photo, which can take a while for 20, so it runs beside the page
  # (start_async, docs/jobs.md) and the page says Adding… until it lands on the Photos
  # tab. Every photo waits for a team admin.
  @rules [
    "Exercises and events only. Never from an incident.",
    "No one from the public unless they said yes.",
    "No licence plates, house numbers, or maps of a search.",
    "Ask a member before you add a close-up of them."
  ]

  # The ask's link (#1034). A token that was never one is not found.
  def mount(%{"token" => token}, _session, socket) do
    case PhotoAskLinks.find_activity_ask(token, DateTime.utc_now()) do
      {:ok, ask} ->
        {:ok, socket |> assign(token: token) |> assign_asked(ask) |> assign_page()}

      :ended ->
        {:ok, assign_ended(socket)}

      :error ->
        raise Web.Status.NotFound
    end
  end

  def mount(%{"id" => id}, _session, socket) do
    %{current_team: team, team_admin?: team_admin?, current_user: user} = socket.assigns
    activity = ActivityLive.fetch_activity(team, id)
    now = DateTime.utc_now()
    # Who adds: the member logged in, or a team admin's own member row when they have one.
    who = %{user: user, team_admin?: team_admin?, member: Reply.replier(socket.assigns, now)}
    if !AddActivityPhotos.may_add?(team, activity, who, now), do: raise(Web.Status.NotFound)

    {:ok, socket |> assign(token: nil, team: team, activity: activity, who: who) |> assign_page()}
  end

  # The member the ask names adds to its activity, whoever is logged in: no login is
  # theirs to use. Logged in to the ask's team, the bar names it, as the reply links do.
  defp assign_asked(socket, %ActivityPhotoAsk{team: team, member: member, activity: activity}) do
    socket =
      if Navigation.opens_team?(socket.assigns, team),
        do: assign(socket, current_team: team),
        else: socket

    assign(socket,
      team: team,
      activity: Activity.put_logged_minutes(activity),
      who: %{user: nil, team_admin?: false, member: member}
    )
  end

  defp assign_ended(socket),
    do: assign(socket, page_title: "This link no longer works", ended?: true, done?: false)

  defp assign_page(socket) do
    socket
    |> assign(
      page_title: "#{socket.assigns.activity.title} · Add photos",
      caption: "",
      may_post?: false,
      adding: nil,
      ended?: false,
      done?: false
    )
    |> allow_upload(:photos,
      accept: ~w(image/*),
      max_entries: Service.ActivityPhoto.max_photos(),
      max_file_size: Service.ActivityPhoto.max_bytes(),
      auto_upload: true,
      progress: &handle_progress/3
    )
  end

  # A photo has uploaded: check it reads, and leave it with the upload until Add. One
  # that does not read goes, and the page says which.
  defp handle_progress(:photos, %{done?: true} = entry, socket) do
    checked =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:postpone, path |> File.read!() |> Service.ActivityPhoto.check()}
      end)

    case checked do
      :ok ->
        {:noreply, socket}

      {:error, text} ->
        {:noreply,
         socket
         |> cancel_upload(:photos, entry.ref)
         |> put_flash(:error, "#{entry.client_name}: #{text}")}
    end
  end

  defp handle_progress(:photos, _entry, socket), do: {:noreply, socket}

  def handle_event("validate", params, socket),
    do: {:noreply, socket |> assign_send(params) |> refuse_uploads()}

  def handle_event("remove", %{"ref" => ref}, socket) do
    known? = Enum.any?(socket.assigns.uploads.photos.entries, &(&1.ref == ref))
    {:noreply, if(known?, do: cancel_upload(socket, :photos, ref), else: socket)}
  end

  # A second Add while the first is adding does nothing.
  def handle_event("save", _params, %{assigns: %{adding: count}} = socket) when is_integer(count),
    do: {:noreply, socket}

  def handle_event("save", params, socket) do
    socket = socket |> assign_send(params) |> refuse_uploads()
    entries = socket.assigns.uploads.photos.entries

    cond do
      entries == [] ->
        {:noreply, put_flash(socket, :error, AddActivityPhotos.error_text(:none))}

      # One still on its way, or one removed that has yet to leave the upload.
      Enum.any?(entries, &(!&1.done? or &1.cancelled?)) ->
        {:noreply,
         put_flash(socket, :error, "The photos are still uploading. Add them once they finish.")}

      String.length(socket.assigns.caption) > Service.ActivityPhoto.max_caption() ->
        {:noreply, put_flash(socket, :error, AddActivityPhotos.error_text(:caption))}

      true ->
        {:noreply, if(link_open?(socket), do: add(socket), else: assign_ended(socket))}
    end
  end

  # From the ask's link, it is read again: it may have stopped while the page was open.
  defp link_open?(%{assigns: %{token: nil}}), do: true

  defp link_open?(%{assigns: %{token: token}}),
    do: match?({:ok, _ask}, PhotoAskLinks.find_activity_ask(token, DateTime.utc_now()))

  # The caption and the permission box, kept so a re-render never clears them.
  defp assign_send(socket, params) do
    assign(socket,
      caption: params["caption"] || socket.assigns.caption,
      may_post?: params["may_post"] == "true"
    )
  end

  # The uploads move to a folder of this send's own, and the photos are read beside the
  # page. The folder goes when the reading ends, whatever it did.
  defp add(socket) do
    %{team: team, activity: activity, who: who, caption: caption, may_post?: may_post?} =
      socket.assigns

    dir = Path.join(System.tmp_dir!(), "sarduty-add-photos-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)

    paths =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        kept = Path.join(dir, entry.uuid)
        # The same disk moves it; another disk copies it.
        with {:error, _reason} <- File.rename(path, kept), do: File.cp!(path, kept)
        {:ok, kept}
      end)

    send = %{caption: caption, may_post: may_post?}

    socket
    |> assign(adding: length(paths))
    |> start_async(:add, fn ->
      try do
        AddActivityPhotos.call(team, activity, who, paths, send, DateTime.utc_now())
      after
        File.rm_rf(dir)
      end
    end)
  end

  # Some were added: the Photos tab shows them, and says what was left out.
  def handle_async(:add, {:ok, {:ok, %{added: added} = result}}, socket) when added > 0 do
    %{team: team, activity: activity, token: token} = socket.assigns
    {kind, text} = AddActivityPhotos.result_text(result)
    socket = put_flash(socket, kind, text)

    # From the ask's link the page says so, with nowhere to go without a login.
    if token,
      do: {:noreply, assign(socket, page_title: "Photos added", done?: true, adding: nil)},
      else: {:noreply, push_navigate(socket, to: Web.ActivityPhoto.tab_path(team, activity.id))}
  end

  def handle_async(:add, {:ok, {:ok, result}}, socket) do
    {kind, text} = AddActivityPhotos.result_text(result)
    {:noreply, socket |> assign(adding: nil) |> put_flash(kind, text)}
  end

  def handle_async(:add, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket |> assign(adding: nil) |> put_flash(:error, AddActivityPhotos.error_text(reason))}
  end

  def handle_async(:add, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(adding: nil)
     |> put_flash(:error, "The photos did not save. Add them again.")}
  end

  # A file the upload will not take, such as one over 25 MB, goes, and so does every
  # photo past the 20th, so what is listed is what Add sends.
  defp refuse_uploads(socket) do
    upload = socket.assigns.uploads.photos

    socket = upload |> invalid() |> Enum.reduce(socket, &refuse(&2, upload, &1))
    over = socket.assigns.uploads.photos |> picked() |> Enum.drop(upload.max_entries)

    if over == [] do
      socket
    else
      over
      |> Enum.reduce(socket, &cancel_upload(&2, :photos, &1.ref))
      |> put_flash(:error, "#{AddActivityPhotos.error_text(:too_many)} The rest were left out.")
    end
  end

  defp invalid(upload), do: Enum.reject(upload.entries, & &1.valid?)

  # The photos still picked: one that was removed stays with the upload for a moment.
  defp picked(upload), do: Enum.reject(upload.entries, & &1.cancelled?)

  defp refuse(socket, upload, entry) do
    error = upload |> upload_errors(entry) |> List.first()

    socket
    |> cancel_upload(:photos, entry.ref)
    |> put_flash(:error, "#{entry.client_name}: #{upload_error(error, upload, "photos")}")
  end

  def render(%{ended?: true} = assigns) do
    ~H"""
    <h1 class="title">This link no longer works</h1>
    <p id="photos-link-ended">Ask a team admin for a new one.</p>
    """
  end

  # Added through the ask's link. The link still works, for the photos they find later.
  def render(%{done?: true} = assigns) do
    ~H"""
    <p id="photos-team" class="hint mb-1">{@team.name}</p>
    <h1 class="title">Photos added</h1>
    <p id="photos-link-done" class="lead">
      From {@activity.title}. A team admin looks at them before the team sees them.
    </p>
    <.button id="photos-more" href={~p"/photos/activities/#{@token}"}>Add more photos</.button>
    """
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        rules: @rules,
        entries: picked(assigns.uploads.photos),
        back: Web.ActivityPhoto.tab_path(assigns.team, assigns.activity.id)
      )

    ~H"""
    <.breadcrumbs :if={!@token}>
      <:item label="Activities" path={~p"/teams/#{@team}/activities"} />
      <:item label={@activity.ref_id} path={~p"/teams/#{@team}/activities/#{@activity.id}"} />
      <:item label="Photos" path={@back} />
      <:item label="Add photos" />
    </.breadcrumbs>
    <p :if={@token} id="photos-team" class="hint mb-1">{@team.name}</p>
    <h1 class="title">Add photos</h1>
    <p id="photos-lead" class="lead">
      From {@activity.title}, {Format.date_short(@activity.started_at, @team.timezone)}. A team admin looks at them before the team sees them.
    </p>

    <h2 class="subheading">Before you add</h2>
    <ul id="photos-rules" class="activity-photo-rules">
      <li :for={rule <- @rules}>{rule}</li>
    </ul>

    <form id="photos-form" phx-change="validate" phx-submit="save">
      <div id="photos-pick" phx-hook="PhotoPick" class="mb-6">
        <span id="photos-label" class="label block mb-1">Photos</span>
        <.hint>
          Up to {Service.ActivityPhoto.max_photos()} at a time, {Format.file_size(
            Service.ActivityPhoto.max_bytes()
          )} each.
        </.hint>
        <div class="flex flex-wrap gap-2">
          <%!-- The camera on the back of the phone: the photo is of the activity. --%>
          <.button
            id="photos-take"
            type="button"
            disabled={@adding != nil}
            data-photo-pick="camera"
            data-photo-capture="environment"
          >
            Take a photo
          </.button>
          <.button
            id="photos-select"
            type="button"
            disabled={@adding != nil}
            data-photo-pick="file"
          >
            Select photos
          </.button>
        </div>
        <%!-- Both buttons open this one input: Take a photo with the camera asked for. --%>
        <.live_file_input upload={@uploads.photos} class="hidden" aria-labelledby="photos-label" />

        <ul :if={@entries != []} id="photos-picked" class="activity-photo-files">
          <li :for={entry <- @entries} id={"photos-entry-#{entry.ref}"}>
            <%!-- A phone's own preview. A browser that cannot draw the file leaves the tile plain. --%>
            <span class="activity-photo-tile">
              <.live_img_preview entry={entry} alt="" data-hide-on-error />
            </span>
            <div>
              <strong class="block">{entry.client_name}</strong>
              <span class="hint block">
                {Format.file_size(entry.client_size)}{if !entry.done?,
                  do: " · Uploading"}
              </span>
              <.a
                id={"photos-remove-#{entry.ref}"}
                href="#"
                phx-click="remove"
                phx-value-ref={entry.ref}
              >Remove</.a>
            </div>
          </li>
        </ul>
        <.spinner :if={@adding} id="photos-adding" class="block mt-4">
          {Format.count(@adding, one: "Adding %d photo…", many: "Adding %d photos…")}
        </.spinner>
      </div>

      <.input
        type="textarea"
        id="photos-caption"
        name="caption"
        label="Caption (optional)"
        value={@caption}
        rows="2"
        maxlength={Service.ActivityPhoto.max_caption()}
      >
        What is happening. The team may use it in a post.
      </.input>

      <.input
        type="checkbox"
        id="photos-may-post"
        name="may_post"
        label={"#{@team.name} may post these on its website and social media."}
        checked={@may_post?}
      >
        You keep them. Ask a team admin to take one down at any time.
      </.input>

      <.form_actions class="mt-6">
        <.button
          id="photos-save"
          variant={:success}
          disabled={@adding != nil}
          phx-disable-with="Adding…"
        >
          {save_text(@adding, length(@entries))}
        </.button>
        <%!-- The ask's link has nowhere to go back to without a login. --%>
        <.button :if={!@token} id="photos-cancel" navigate={@back}>Cancel</.button>
      </.form_actions>
    </form>
    """
  end

  # The button counts what it adds: "Add 3 photos". While it adds, it says so.
  defp save_text(adding, _picked) when is_integer(adding), do: "Adding…"
  defp save_text(nil, 0), do: "Add photos"

  defp save_text(nil, picked),
    do: Format.count(picked, one: "Add %d photo", many: "Add %d photos")
end
