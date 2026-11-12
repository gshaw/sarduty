defmodule Web.MemberPhotoController do
  use Web, :controller

  alias App.Model.MemberPhoto
  alias App.Model.MemberPhotoFile
  alias App.Model.Team

  # A photo a member added (#1029), while it waits and SAR Duty keeps it: one URL for
  # everyone, as a certificate's file has. A team admin gets any of the team's; anyone
  # else only their own, so a team admin viewing as a member gets the member's.
  # `?shape=placed` is the square the member placed, as their ID card would show it,
  # cut from the photo their Clean up switch showed (#1031); `?shape=cleaned` the
  # cleaned-up photo, for one that has it; and without either, the photo as taken.
  def file(conn, %{"id" => id} = params) do
    %{current_team: team, current_member: member, team_admin?: team_admin?} = conn.assigns
    if !Team.photos?(team), do: raise(Web.Status.NotFound)

    photo =
      if team_admin?,
        do: MemberPhoto.find!(team, id),
        else: MemberPhoto.find_for_member!(member, id)

    case jpeg(photo, params["shape"]) do
      {:ok, jpeg} ->
        conn
        |> put_resp_content_type("image/jpeg", nil)
        # The member can replace it while it waits, and it goes once decided.
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> send_resp(200, jpeg)

      _gone ->
        send_resp(conn, :not_found, "")
    end
  end

  defp jpeg(photo, "placed") do
    with bytes when is_binary(bytes) <-
           MemberPhotoFile.bytes(photo, MemberPhoto.shape(photo, photo.clean_up)) do
      {turns, square} = MemberPhoto.placed(photo)
      Service.MemberPhoto.place(bytes, turns, square)
    end
  end

  defp jpeg(photo, shape) do
    shape = if shape == "cleaned", do: :cleaned, else: :taken
    with bytes when is_binary(bytes) <- MemberPhotoFile.bytes(photo, shape), do: {:ok, bytes}
  end
end
