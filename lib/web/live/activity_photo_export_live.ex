defmodule Web.ActivityPhotoExportLive do
  @moduledoc """
  Export for a post, /teams/:subdomain/photos/:id/export (#1032, part 9): whoever posts
  for the team, a team admin, takes a copy of an accepted photo the team may post. They
  pick a shape, place a box of that shape over the photo as edited, and download a JPEG
  at the shape's size, with the caption ready to copy.

  The box is placed with Add a photo's hook (assets/js/photo_place.js), which fills the
  form's `photo[x]`, `photo[y]`, and `photo[side]`. Download JPEG is a plain GET of the
  form to Web.ActivityPhotoController's `export`, so the browser saves the file and the
  page stays. Nothing is saved: a new shape, or the next visit, starts the box afresh.

  A photo the team may not post opens its page, which says why.
  """
  use Web, :live_view_app_layout

  import Web.Components.CopyButton, only: [copy_button: 1]

  alias App.Model.ActivityPhoto
  alias App.Operation.AddActivityPhotos
  alias App.Operation.ExportActivityPhoto
  alias Service.Format
  alias Service.PhotoExport

  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    if !AddActivityPhotos.available?(team), do: raise(Web.Status.NotFound)
    if !match?({_id, ""}, Integer.parse(id)), do: raise(Web.Status.NotFound)

    photo = ActivityPhoto.find_accepted!(team, id, %{team_admin?: true, member: nil})

    case ExportActivityPhoto.check(photo) do
      :ok ->
        {:ok,
         assign(socket,
           photo: photo,
           page_title: "Export for a post",
           shape: PhotoExport.shape(nil),
           caption: Web.ActivityPhoto.post_caption(photo, team, DateTime.utc_now())
         )}

      {:error, :may_not_post} ->
        {:ok,
         socket
         |> put_flash(:error, Web.ActivityPhoto.may_not_post_text(photo))
         |> push_navigate(to: Web.ActivityPhoto.page_path(team, photo))}
    end
  end

  def handle_event("shape", %{"shape" => key}, socket),
    do: {:noreply, assign(socket, shape: PhotoExport.shape(key))}

  def handle_event("shape", _params, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Photos" path={Web.PhotoCollectionLive.path(@current_team)} />
      <:item
        label={"Photo from #{@photo.activity.title}"}
        path={Web.ActivityPhoto.page_path(@current_team, @photo)}
      />
      <:item label="Export for a post" />
    </.breadcrumbs>
    <h1 class="title">Export for a post</h1>
    <p class="lead">
      Pick the shape the post needs, place the box, and download. The photo itself does not change.
    </p>

    <%!-- A plain GET: the browser saves the JPEG and the page stays. --%>
    <form
      id="photo-export"
      action={Web.ActivityPhoto.export_file_path(@current_team, @photo)}
      method="get"
      phx-change="shape"
    >
      <div class="cert-layout">
        <div class="cert-layout-file photo-export">
          <Web.ActivityPhoto.export_box
            id={"photo-export-box-#{@shape.key}"}
            team={@current_team}
            photo={@photo}
            ratio={PhotoExport.ratio(@shape, ExportActivityPhoto.size(@photo))}
            hint_id="photo-export-hint"
          />
          <p id="photo-export-hint" class="hint mt-2">
            Drag the box to move it. Pinch or scroll to zoom.
          </p>
        </div>

        <aside class="cert-layout-panel">
          <.input
            id="photo-shape"
            type="radios"
            name="shape"
            label="Shape"
            value={@shape.key}
            options={Enum.map(PhotoExport.shapes(), &shape_option(&1, @photo))}
          />

          <div :if={@caption} id="photo-caption" class="mb-6">
            <p class="label mb-1">Caption</p>
            <p id="photo-caption-text" class="mb-1">
              <.copy_button
                id="photo-caption-copy"
                value={@caption}
                text={@caption}
                label="Copy caption"
              />
            </p>
            <.hint>With credit to who took it.</.hint>
          </div>

          <.form_actions>
            <.button id="photo-download" type="submit" variant={:success}>
              Download JPEG
            </.button>
            <.button id="photo-cancel" navigate={Web.ActivityPhoto.page_path(@current_team, @photo)}>
              Cancel
            </.button>
          </.form_actions>
        </aside>
      </div>
    </form>
    """
  end

  # "Portrait 4:5", with "1080 × 1350 · Instagram feed" under it. Original says the size
  # of the photo as edited.
  defp shape_option(%{size: nil} = shape, photo),
    do: {shape.label, shape.key, hint(ExportActivityPhoto.size(photo), shape.used_for)}

  defp shape_option(shape, _photo),
    do: {shape.label, shape.key, hint(shape.size, shape.used_for)}

  defp hint(size, used_for), do: "#{Format.image_size(size)} · #{used_for}"
end
