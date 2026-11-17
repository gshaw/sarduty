defmodule App.Operation.AddOwnPhoto do
  @moduledoc """
  A member adds their own photo (#1029). It waits for a team admin, who accepts it
  (App.Operation.AcceptMemberPhoto) or declines it (App.Operation.DeclineMemberPhoto):
  a member never changes their own photo without one. Nothing here reaches the team's
  records, and the member's ID card keeps the photo it has.

  SAR Duty keeps the photo as taken, the copy Service.MemberPhoto.prepare/1 made, and
  where the member placed it, so a team admin can place it again. With Clean up (#1031)
  it keeps the cleaned-up photo too, and whether the member left the switch on. A member has one
  waiting photo: a new one replaces it. Adding one closes a team admin's ask for it
  (App.Operation.AskForPhoto).
  """

  import Ecto.Query

  alias App.Model.Member
  alias App.Model.MemberPhoto
  alias App.Model.MemberPhotoFile
  alias App.Model.PhotoAsk
  alias App.Repo

  @doc """
  `photo` is `%{bytes:, width:, height:}` from Service.MemberPhoto.prepare/1, and
  `placed` where the member put it, as Service.MemberPhoto.placement/1 reads the form.
  With Clean up (#1031), `clean_up` is `{cleaned, on?}`: the cleaned-up photo, as
  App.Operation.CleanUpPhoto gives it, and whether the Clean up switch was on, so
  whether `placed` is on the cleaned-up photo. Both photos are kept. It is nil with
  Clean up off, or when it did not answer. `{:ok, member_photo}`.
  """
  def call(member, photo, placed, clean_up \\ nil)

  def call(%Member{} = member, %{bytes: bytes, width: width, height: height}, placed, clean_up)
      when is_binary(bytes) do
    {turns, square} = Service.MemberPhoto.normalize(placed)
    {cleaned, on?} = clean_up || {%{bytes: nil, width: nil, height: nil}, false}

    row = %MemberPhoto{
      team_id: member.team_id,
      member_id: member.id,
      width: width,
      height: height,
      turns: turns,
      x: square.x,
      y: square.y,
      side: square.side,
      clean_up: on?,
      cleaned_width: cleaned.width,
      cleaned_height: cleaned.height
    }

    MemberPhoto.locked(member.id, fn ->
      Repo.transaction(fn ->
        delete_waiting(member)
        photo = Repo.insert!(row)
        MemberPhotoFile.put!(photo, bytes, cleaned.bytes)
        # They answered a team admin's ask (#1030), so its link stops working.
        PhotoAsk.close_for_member(member, DateTime.utc_now())
        photo
      end)
    end)
  end

  # The photo that waited goes, with its file: it was never decided, so nothing is lost.
  defp delete_waiting(member) do
    waiting =
      MemberPhoto
      |> where([p], p.team_id == ^member.team_id and p.member_id == ^member.id)
      |> where([p], p.status == :waiting)

    MemberPhotoFile
    |> where([f], f.member_photo_id in subquery(select(waiting, [p], p.id)))
    |> Repo.delete_all()

    Repo.delete_all(waiting)
  end
end
