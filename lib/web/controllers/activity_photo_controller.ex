defmodule Web.ActivityPhotoController do
  use Web, :controller

  alias App.Model.ActivityPhoto
  alias App.Operation.AddActivityPhotos
  alias App.Operation.ExportActivityPhoto
  alias App.Operation.LoadActivityPhoto

  # An activity photo's file (#1032): one URL for everyone on the team, as a member's
  # photo has. An accepted photo is anyone's on the team. A waiting one is a team
  # admin's, or the member's who added it, and not found for anyone else
  # (ActivityPhoto.find_visible!/3), so a team admin viewing as a member gets what the
  # member gets. `?size=` picks the file: `tile`, `show`, the default, or `original`.
  @sizes %{"tile" => :tile, "show" => :show, "original" => :original}

  def file(conn, %{"id" => id} = params) do
    %{current_team: team, current_member: member, team_admin?: team_admin?} = conn.assigns
    if !AddActivityPhotos.available?(team), do: raise(Web.Status.NotFound)

    size = Map.get(@sizes, params["size"] || "show")
    if !size or !integer?(id), do: raise(Web.Status.NotFound)

    photo = ActivityPhoto.find_visible!(team, id, %{team_admin?: team_admin?, member: member})

    case LoadActivityPhoto.call(photo, size) do
      {:ok, jpeg} ->
        conn
        |> put_resp_content_type("image/jpeg", nil)
        |> put_resp_header("cache-control", cache(photo))
        |> put_resp_header("x-content-type-options", "nosniff")
        |> send_resp(200, jpeg)

      :error ->
        send_resp(conn, :not_found, "")
    end
  end

  # Export for a post (#1032, part 9), for team admins: the box's part of the photo as
  # edited, at the shape's size, as a JPEG to save. `shape` and `photo[x]`, `photo[y]`,
  # and `photo[side]` come from Web.ActivityPhotoExportLive's form. Nothing is saved.
  def export(conn, %{"id" => id} = params) do
    team = conn.assigns.current_team
    if !AddActivityPhotos.available?(team) or !integer?(id), do: raise(Web.Status.NotFound)

    placed = if is_map(params["photo"]), do: params["photo"], else: %{}
    {_turns, box} = Service.MemberPhoto.placement(placed)
    shape = Service.PhotoExport.shape(params["shape"])

    case ExportActivityPhoto.call(team, id, shape.key, box) do
      {:ok, jpeg} ->
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> send_download({:binary, jpeg},
          filename: "photo-#{id}-#{shape.key}.jpg",
          content_type: "image/jpeg"
        )

      {:error, :files} ->
        conn
        |> put_flash(:error, "The photo did not export. Download it again.")
        |> redirect(to: ~p"/teams/#{team}/photos/#{id}/export")

      # The page never offers one the team may not post.
      {:error, _may_not} ->
        raise Web.Status.NotFound
    end
  end

  # An accepted photo's files never change under one URL, which carries when the photo
  # last changed (Web.ActivityPhoto.file_path/3), so a browser keeps them a day. Private: the
  # route needs a login. A waiting photo can be deleted at any time, so nothing keeps it.
  defp cache(%ActivityPhoto{status: :accepted}), do: "private, max-age=86400, immutable"
  defp cache(%ActivityPhoto{}), do: "private, no-store"

  defp integer?(id), do: match?({_integer, ""}, Integer.parse(id))
end
