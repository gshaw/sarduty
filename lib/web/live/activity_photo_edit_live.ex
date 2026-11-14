defmodule Web.ActivityPhotoEditLive do
  @moduledoc """
  Edit photo, /teams/:subdomain/photos/:id/edit (#1032, part 8): a team admin fixes an
  accepted photo, on the layout a member photo is checked on. The photo as the team will
  see it, under a grid to straighten against; Rotate left and Rotate right, in quarter
  turns; Straighten, from −10° to 10°; and Clean up, while it is available. Beside it,
  the photo as taken. No crop, and no sliders for light or colour.

  The page shows the edit with the browser's own turn and zoom on the original, so
  nothing is made until Save (App.Operation.EditActivityPhoto). Clean up is the one
  change a browser cannot show: turning it on fetches the cleaned-up photo once, in
  `start_async`, and the turns apply to it the same way.

  A waiting photo opens its activity's Photos tab, where Accept is.
  """
  use Web, :live_view_app_layout

  alias App.Model.ActivityPhoto
  alias App.Model.Member
  alias App.Operation.AddActivityPhotos
  alias App.Operation.EditActivityPhoto
  alias Service.Format

  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    if !AddActivityPhotos.available?(team), do: raise(Web.Status.NotFound)
    if !match?({_id, ""}, Integer.parse(id)), do: raise(Web.Status.NotFound)
    admin = %{team_admin?: true, member: nil}

    case team |> ActivityPhoto.find_visible!(id, admin) |> EditActivityPhoto.check() do
      :ok -> {:ok, socket |> load(ActivityPhoto.find_accepted!(team, id, admin))}
      {:error, :waiting} -> {:ok, waiting(socket, ActivityPhoto.find_visible!(team, id, admin))}
    end
  end

  defp load(socket, photo) do
    clean_up_available? = EditActivityPhoto.clean_up_available?()

    socket
    |> assign(photo: photo, page_title: "Edit photo", now: DateTime.utc_now())
    |> assign(turns: photo.turns, angle: photo.angle)
    |> assign(clean_up_available?: clean_up_available?, preview: nil, cleaning?: false)
    |> assign(clean_up?: clean_up_available? and photo.clean_up)
    |> then(&if &1.assigns.clean_up?, do: clean_up_preview(&1), else: &1)
  end

  defp waiting(socket, photo) do
    socket
    |> put_flash(:error, "Accept the photo first.")
    |> push_navigate(
      to: Web.ActivityPhoto.tab_path(socket.assigns.current_team, photo.activity_id)
    )
  end

  def handle_event("rotate", %{"direction" => direction}, socket) do
    turn = if direction == "left", do: -1, else: 1
    {:noreply, update(socket, :turns, &Integer.mod(&1 + turn, 4))}
  end

  def handle_event("straighten", %{"angle" => angle}, socket) do
    case Float.parse(angle) do
      {angle, _rest} ->
        %{angle: angle} =
          Service.ActivityPhoto.settings(%{turns: 0, angle: angle, clean_up: false})

        {:noreply, assign(socket, angle: angle)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("clean-up", _params, socket) do
    socket = update(socket, :clean_up?, &(!&1))
    {:noreply, if(socket.assigns.clean_up?, do: clean_up_preview(socket), else: socket)}
  end

  def handle_event("save", _params, socket) do
    %{current_team: team, current_user: user, photo: photo} = socket.assigns
    %{turns: turns, angle: angle, clean_up?: clean_up?} = socket.assigns
    settings = %{turns: turns, angle: angle, clean_up: clean_up?}

    case EditActivityPhoto.call(team, photo, settings, user, DateTime.utc_now()) do
      {:ok, saved} ->
        {kind, text} = saved_text(clean_up?, saved)

        {:noreply,
         socket
         |> put_flash(kind, text)
         |> push_navigate(to: Web.ActivityPhoto.page_path(team, photo))}

      {:error, reason} ->
        {:noreply, not_saved(socket, reason)}
    end
  end

  defp not_saved(socket, :waiting), do: waiting(socket, socket.assigns.photo)

  defp not_saved(socket, :gone) do
    socket
    |> put_flash(:error, "This photo was deleted.")
    |> push_navigate(to: Web.PhotoCollectionLive.path(socket.assigns.current_team))
  end

  defp not_saved(socket, :files),
    do: put_flash(socket, :error, "The photo did not save. Save it again.")

  # Clean up asked for and not on the photo saved means it did not answer.
  defp saved_text(true, %ActivityPhoto{clean_up: false}),
    do: {:error, "Clean up did not answer. The photo is saved without it."}

  defp saved_text(_clean_up?, _saved), do: {:info, "Photo saved."}

  # The cleaned-up photo, fetched once: the switch shows it from then on.
  defp clean_up_preview(%{assigns: %{preview: preview}} = socket) when is_binary(preview),
    do: socket

  defp clean_up_preview(socket) do
    if connected?(socket) do
      photo = socket.assigns.photo

      socket
      |> assign(cleaning?: true)
      |> start_async(:preview, fn -> EditActivityPhoto.preview(photo) end)
    else
      socket
    end
  end

  def handle_async(:preview, {:ok, {:ok, jpeg}}, socket),
    do:
      {:noreply,
       assign(socket, preview: "data:image/jpeg;base64," <> Base.encode64(jpeg), cleaning?: false)}

  def handle_async(:preview, _did_not_answer, socket) do
    {:noreply,
     socket
     |> assign(clean_up?: false, cleaning?: false)
     |> put_flash(:error, "Clean up did not answer. Turn it on again to try again.")}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Photos" path={Web.PhotoCollectionLive.path(@current_team)} />
      <:item
        label={"Photo from #{@photo.activity.title}"}
        path={Web.ActivityPhoto.page_path(@current_team, @photo)}
      />
      <:item label="Edit photo" />
    </.breadcrumbs>
    <h1 class="title">Edit photo</h1>

    <div class="cert-layout">
      <div class="cert-layout-file">
        <div id="photo-edit" class="photo-edit" style={frame_style(@photo, @turns, @angle)}>
          <img
            id="photo-edit-image"
            src={
              if @clean_up? and @preview,
                do: @preview,
                else: Web.ActivityPhoto.file_path(@current_team, @photo, :original)
            }
            alt={Web.ActivityPhoto.alt(@photo)}
            width={@photo.width}
            height={@photo.height}
          />
          <div class="photo-edit-grid" aria-hidden="true"></div>
        </div>
        <p :if={@cleaning?} id="photo-cleaning" class="hint mt-2" role="status">Cleaning up…</p>

        <div class="photo-edit-tools">
          <.button
            id="photo-rotate-left"
            type="button"
            icon="rotate-ccw-square"
            phx-click="rotate"
            phx-value-direction="left"
          >
            Rotate left
          </.button>
          <.button
            id="photo-rotate-right"
            type="button"
            icon="rotate-cw-square"
            phx-click="rotate"
            phx-value-direction="right"
          >
            Rotate right
          </.button>
        </div>

        <%!-- The slider takes effect as it moves; Save, beside, saves the page. --%>
        <form
          id="photo-straighten"
          class="photo-edit-straighten"
          phx-change="straighten"
          phx-submit="straighten"
        >
          <.label for="photo-angle">Straighten</.label>
          <div>
            <span aria-hidden="true">{Format.degrees(-Service.ActivityPhoto.max_angle())}</span>
            <input
              id="photo-angle"
              type="range"
              name="angle"
              min={-Service.ActivityPhoto.max_angle()}
              max={Service.ActivityPhoto.max_angle()}
              step={Service.ActivityPhoto.angle_step()}
              value={@angle}
              aria-valuetext={Format.degrees(@angle)}
            />
            <span aria-hidden="true">{Format.degrees(Service.ActivityPhoto.max_angle())}</span>
          </div>
        </form>

        <.switch
          :if={@clean_up_available?}
          id="photo-clean-up"
          label="Clean up"
          checked={@clean_up?}
          phx-click="clean-up"
          class="photo-edit-switch"
        >
          Levels the horizon and fixes the light and colour. {keep_text(@photo)}
        </.switch>
      </div>

      <aside class="cert-layout-panel">
        <dl id="photo-details" class="mb-8">
          <dt>Activity</dt>
          <dd>
            <.a
              id="photo-activity"
              navigate={Web.ActivityPhoto.tab_path(@current_team, @photo.activity_id)}
            >{@photo.activity.title}</.a>
          </dd>
          <dt>Added by</dt>
          <dd id="photo-added">{Web.ActivityPhoto.added_on(@photo, @current_team, @now)}</dd>
          <dt>As taken</dt>
          <dd>
            <img
              id="photo-as-taken"
              class="photo-edit-taken"
              src={Web.ActivityPhoto.file_path(@current_team, @photo, :original)}
              alt=""
            />
          </dd>
        </dl>
        <p class="hint">
          The team sees the result. {original_text(@photo)}
        </p>
        <.form_actions>
          <.button
            id="photo-save"
            type="button"
            variant={:success}
            phx-click="save"
            phx-disable-with="Saving…"
            disabled={@cleaning?}
          >
            Save
          </.button>
          <.button id="photo-cancel" navigate={Web.ActivityPhoto.page_path(@current_team, @photo)}>
            Cancel
          </.button>
        </.form_actions>
      </aside>
    </div>
    """
  end

  # The browser's turn and zoom on the original, as Service.ActivityPhoto.plan/2 does
  # them: the frame takes the turned photo's shape, and the photo is zoomed just enough
  # that the straightened cut leaves no empty corners.
  defp frame_style(photo, turns, angle) do
    {width, height} = {photo.width, photo.height}
    {turned_width, turned_height} = Service.ActivityPhoto.turned_size(turns, {width, height})
    zoom = 1 / Service.ActivityPhoto.cut_scale(angle, {turned_width, turned_height})

    Enum.join(
      [
        "--photo-ratio: #{turned_width} / #{turned_height}",
        "--photo-width: #{Float.round(width / turned_width * 100, 4)}%",
        "--photo-turn: #{turns * 90 + angle}deg",
        "--photo-zoom: #{Float.round(zoom, 4)}"
      ],
      "; "
    )
  end

  # Who took it, by first name: the member who added it. A team admin with no member
  # row, or a member since removed, has no name to give.
  defp keep_text(%ActivityPhoto{member: %Member{} = member}),
    do: "Turn it off to keep the photo as #{Member.first_name(member)} took it."

  defp keep_text(%ActivityPhoto{}), do: "Turn it off to keep the photo as it was taken."

  defp original_text(%ActivityPhoto{member: %Member{} = member}),
    do:
      "#{Member.first_name(member)}'s original stays as it came, and Revert to original brings it back."

  defp original_text(%ActivityPhoto{}),
    do: "The original stays as it came, and Revert to original brings it back."
end
