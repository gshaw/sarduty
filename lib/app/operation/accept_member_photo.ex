defmodule App.Operation.AcceptMemberPhoto do
  @moduledoc """
  A team admin accepts a photo a member added (#1029). The square as the team admin
  placed it is cut from the photo the Clean up switch shows (#1031) and sent through
  App.Operation.SetMemberPhoto, as a team admin's own Add a photo is: one change set
  row, `has_photo`, and the member's ID card on their phones again. Then SAR Duty
  deletes its copy of the photo, and the row stays with who accepted it and when.

  A send the team's records refuse leaves the photo waiting, with its file, to try
  again.
  """

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.MemberPhoto
  alias App.Model.MemberPhotoFile
  alias App.Model.Team
  alias App.Operation.SetMemberPhoto
  alias App.Repo

  @doc """
  `placed` is where the team admin left the square, as Service.MemberPhoto.placement/1
  reads the form, and `clean_up?` where they left the Clean up switch (#1031): on, the
  square is cut from the cleaned-up photo, and off, or for a photo with no cleaned-up
  copy, from the photo as taken. `{:ok, member_photo}`; `{:error, :decided}` once it is
  accepted, declined, or replaced by the member; `{:error, text}` when the send was
  refused; or `{:error, reason}` for a photo that cannot be cut.
  """
  def call(
        %Team{} = team,
        %MemberPhoto{team_id: team_id} = photo,
        placed,
        clean_up?,
        %User{} = user,
        now
      )
      when team_id == team.id and is_boolean(clean_up?) do
    # The lock is held while the photo is sent, and no transaction is: one would hold
    # SQLite's write lock for as long as the team's records take to answer (#385).
    MemberPhoto.locked(photo.member_id, fn ->
      accept(team, photo, placed, clean_up?, user, now)
    end)
  end

  defp accept(team, photo, placed, clean_up?, user, now) do
    {turns, square} = Service.MemberPhoto.normalize(placed)

    with {:ok, current, shape, bytes} <- waiting(team, photo, clean_up?),
         {:ok, jpeg} <- Service.MemberPhoto.place(bytes, turns, square),
         member = Member.find!(team, current.member_id),
         :ok <- SetMemberPhoto.call(team, member, jpeg, user, now) do
      accepted(current, turns, square, shape == :cleaned, user, now)
    end
  end

  defp waiting(team, photo, clean_up?) do
    with %MemberPhoto{status: :waiting} = current <-
           Repo.get_by(MemberPhoto, id: photo.id, team_id: team.id),
         shape = MemberPhoto.shape(current, clean_up?),
         bytes when is_binary(bytes) <- MemberPhotoFile.bytes(current, shape) do
      {:ok, current, shape, bytes}
    else
      _decided -> {:error, :decided}
    end
  end

  defp accepted(current, turns, square, clean_up?, user, now) do
    Repo.transaction(fn ->
      MemberPhotoFile.delete!(current)

      current
      |> Ecto.Changeset.change(
        status: :accepted,
        turns: turns,
        x: square.x,
        y: square.y,
        side: square.side,
        clean_up: clean_up?,
        decided_by_user_id: user.id,
        decided_at: now
      )
      |> Repo.update!()
    end)
  end
end
