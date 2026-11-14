defmodule Web.ActivityPhotoLive do
  @moduledoc """
  One photo, /teams/:subdomain/photos/:id (#1033): an accepted activity photo, for
  everyone on the team. A waiting photo has no page, and neither has one whose activity
  no longer takes photos (App.Model.ActivityPhoto.find_accepted!/3).

  The photo, then who added it, its activity, its caption, and whether the team may
  post it. Everyone stars it, once: the button counts the stars and never says whose
  they are. A team admin features it on its activity's Overview, downloads the
  original, and deletes it, which is how a photo is taken down when someone in it asks.
  Edit photo (#1032, part 8) fixes it, and the page then says who edited it and when,
  with Revert to original. Export for a post (part 9) takes a copy for a post, on a
  photo the team may post; on one it may not, the action is greyed and says why.

  Members send only `star`. A team admin viewing as a member is told nothing is saved.
  """
  use Web, {:live_view_app_layout, access: :team, member_events: ["star"]}

  alias App.Model.ActivityPhoto
  alias App.Model.Member
  alias App.Operation.AddActivityPhotos
  alias App.Operation.DeleteActivityPhoto
  alias App.Operation.EditActivityPhoto
  alias App.Operation.FeatureActivityPhoto
  alias App.Operation.StarActivityPhoto
  alias Service.Format
  alias Web.PhotoCollectionLive

  def mount(%{"id" => id}, _session, socket) do
    %{current_team: team} = socket.assigns
    if !AddActivityPhotos.available?(team), do: raise(Web.Status.NotFound)
    if !match?({_id, ""}, Integer.parse(id)), do: raise(Web.Status.NotFound)

    {:ok, socket |> assign(now: DateTime.utc_now()) |> load(id)}
  end

  # The photo as it is now, with its stars. One deleted since is not found.
  defp load(socket, id) do
    %{current_team: team, team_admin?: team_admin?, current_user: user} = socket.assigns
    viewer = %{team_admin?: team_admin?, member: socket.assigns.current_member}
    [photo] = [ActivityPhoto.find_accepted!(team, id, viewer)] |> ActivityPhoto.put_stars(user)

    assign(socket, photo: photo, page_title: "Photo from #{photo.activity.title}")
  end

  def handle_event("star", _params, socket) do
    %{photo: photo, current_user: user} = socket.assigns
    {:ok, _starred?} = StarActivityPhoto.call(photo, user)
    {:noreply, load(socket, photo.id)}
  end

  def handle_event("feature", _params, socket), do: {:noreply, feature(socket, true)}
  def handle_event("stop-featuring", _params, socket), do: {:noreply, feature(socket, false)}

  def handle_event("revert", _params, socket) do
    %{current_team: team, photo: photo} = socket.assigns

    case EditActivityPhoto.revert(team, photo, DateTime.utc_now()) do
      {:ok, _photo} ->
        {:noreply,
         socket |> load(photo.id) |> put_flash(:info, "Photo reverted to the original.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "The photo did not revert. Revert it again.")}
    end
  end

  def handle_event("delete", _params, socket) do
    %{current_team: team, photo: photo} = socket.assigns

    case DeleteActivityPhoto.call(team, photo) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Photo deleted.")
         |> push_navigate(to: Web.ActivityPhoto.tab_path(team, photo.activity_id))}

      {:error, :files} ->
        {:noreply, put_flash(socket, :error, "The photo did not delete. Delete it again.")}
    end
  end

  defp feature(socket, featured?) do
    photo = socket.assigns.photo

    case FeatureActivityPhoto.call(photo, featured?, DateTime.utc_now()) do
      {:ok, _photo} ->
        text = if featured?, do: "Photo featured.", else: "Photo no longer featured."
        socket |> load(photo.id) |> put_flash(:info, text)

      {:error, reason} ->
        put_flash(socket, :error, FeatureActivityPhoto.error_text(reason))
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Photos" path={PhotoCollectionLive.path(@current_team)} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <div class="cert-layout">
      <div class="cert-layout-file">
        <a
          id="photo-open"
          class="activity-photo-show"
          href={Web.ActivityPhoto.file_path(@current_team, @photo, :show)}
          target="_blank"
        >
          <img
            id="photo-image"
            src={Web.ActivityPhoto.file_path(@current_team, @photo, :show)}
            alt={Web.ActivityPhoto.alt(@photo)}
            width={elem(ActivityPhoto.shown_size(@photo), 0)}
            height={elem(ActivityPhoto.shown_size(@photo), 1)}
          />
        </a>
        <p :if={@photo.edited_at} id="photo-edited" class="hint mt-2">
          {edited_text(@photo, @current_team, @now)}
          <span :if={@team_admin?}>
            ·
            <.a id="photo-revert" href="#" phx-click="revert" phx-disable-with="Reverting…">Revert to original</.a>
          </span>
        </p>
        <div class="activity-photo-star">
          <.button
            id="photo-star"
            type="button"
            icon={if @photo.starred, do: "star-filled", else: "star"}
            phx-click="star"
            aria-pressed={to_string(@photo.starred)}
          >
            {if @photo.starred, do: "Starred", else: "Star"}
            <span id="photo-stars" class="activity-photo-star-count">
              {Format.number(@photo.stars)}
            </span>
          </.button>
          <.badge :if={@photo.featured_at} id="photo-featured">Featured</.badge>
        </div>
      </div>
      <aside class="cert-layout-panel">
        <dl id="photo-details">
          <dt>Added by</dt>
          <dd id="photo-added">{Web.ActivityPhoto.added_on(@photo, @current_team, @now)}</dd>
          <dt>Activity</dt>
          <dd>
            <.a
              id="photo-activity"
              navigate={Web.ActivityPhoto.tab_path(@current_team, @photo.activity_id)}
            >{@photo.activity.title}</.a>
            <span class="hint block">
              {Format.date_short(@photo.activity.started_at, @current_team.timezone)}
            </span>
          </dd>
          <div :if={@photo.caption}>
            <dt>Caption</dt>
            <dd id="photo-caption">{@photo.caption}</dd>
          </div>
          <dt>Posting</dt>
          <dd id="photo-posting">
            {if @photo.may_post, do: "#{@current_team.name} may post it.", else: "For the team only."}
          </dd>
          <div :if={@team_admin?}>
            <dt>Actions</dt>
            <dd>
              <ul id="photo-actions" class="action-list">
                <li>
                  <.a id="photo-edit" navigate={Web.ActivityPhoto.edit_path(@current_team, @photo)}>Edit photo</.a>
                </li>
                <li :if={!@photo.featured_at}>
                  <.a id="photo-feature" href="#" phx-click="feature">Feature</.a>
                </li>
                <li :if={@photo.featured_at}>
                  <.a id="photo-stop-featuring" href="#" phx-click="stop-featuring">Stop featuring</.a>
                </li>
                <li :if={@photo.may_post}>
                  <.a
                    id="photo-export"
                    navigate={Web.ActivityPhoto.export_path(@current_team, @photo)}
                  >Export for a post</.a>
                </li>
                <li :if={!@photo.may_post} id="photo-export-off" class="action-off">
                  Export for a post
                  <span class="hint block">{Web.ActivityPhoto.may_not_post_text(@photo)}</span>
                </li>
                <li>
                  <.a
                    id="photo-download"
                    href={Web.ActivityPhoto.file_path(@current_team, @photo, :original)}
                    download={download_name(@photo)}
                  >Download original</.a>
                </li>
                <li>
                  <.a
                    id="photo-delete"
                    href="#"
                    phx-click="delete"
                    phx-disable-with="Deleting…"
                    {Web.DeleteConfirm.photo()}
                  >Delete photo</.a>
                </li>
              </ul>
            </dd>
          </div>
        </dl>
      </aside>
    </div>
    """
  end

  # "Edited by Alex Chen, Nov 12, 2026", or with nobody left to name, "Edited Nov 12, 2026".
  defp edited_text(photo, team, now) do
    date = Format.date_short(photo.edited_at, team.timezone)

    case Member.name_for_user(team, photo.edited_by_user, now) do
      nil -> "Edited #{date}"
      name -> "Edited by #{name}, #{date}"
    end
  end

  # The file's name on the team admin's disk.
  defp download_name(photo), do: "photo-#{photo.id}.jpg"
end
