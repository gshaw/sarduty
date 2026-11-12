defmodule App.Operation.DeclineMemberPhoto do
  @moduledoc """
  A team admin declines a photo a member added (#1029), with one reason from
  App.Model.MemberPhoto.reasons/1 and, if they like, a message in their own words. The
  member sees both on their Dashboard and on Add a photo, and adds another. SAR Duty
  deletes its copy of the photo; the row stays, with who declined it, when, and why.
  Nothing reaches the team's records, and no email goes out.
  """

  alias App.Accounts.User
  alias App.Model.MemberPhoto
  alias App.Model.MemberPhotoFile
  alias App.Model.Team
  alias App.Repo

  @doc """
  `{:ok, member_photo}`, `{:error, changeset}` with no reason or too long a message, or
  `{:error, :decided}` once it is accepted, declined, or replaced by the member.
  """
  def call(%Team{} = team, %MemberPhoto{team_id: team_id} = photo, reason, message, user, now)
      when team_id == team.id and is_struct(user, User) do
    decline = fn -> decline(team, photo, reason, message, user, now) end
    MemberPhoto.locked(photo.member_id, fn -> Repo.transaction(decline) end)
  end

  # Inside the transaction: an error rolls it back, and is what `call/6` returns.
  defp decline(team, photo, reason, message, user, now) do
    with %MemberPhoto{status: :waiting} = current <-
           Repo.get_by(MemberPhoto, id: photo.id, team_id: team.id),
         {:ok, declined} <-
           current
           |> MemberPhoto.decline_changeset(reason, message, user, now)
           |> Repo.update() do
      MemberPhotoFile.delete!(declined)
      declined
    else
      {:error, changeset} -> Repo.rollback(changeset)
      _decided -> Repo.rollback(:decided)
    end
  end
end
