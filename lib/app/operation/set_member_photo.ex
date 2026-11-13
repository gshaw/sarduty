defmodule App.Operation.SetMemberPhoto do
  @moduledoc """
  A team admin sets or removes a member's photo in the team's records, D4H or Records
  (#1028). One change set row through App.Operation.ApplyEdit. The row says only that the
  photo changed: the image goes to the team's records and is never kept here.

  The photo goes as a JPEG up to 2400 px with no metadata, the one size for every team:
  big enough for a print or a re-crop later, since the team's records keep it and SAR
  Duty doesn't. Pages and passes read D4H's smaller PREVIEW size. Then
  `has_photo` is set with no download, the member's card goes to their phones again
  (RefreshMemberCard), and Every member gets a card makes theirs the moment a first photo
  is saved (#1012). A photo removed leaves a card already out.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Operation.CheckMemberPhoto
  alias App.Operation.IssueEveryMemberCard
  alias App.Operation.RefreshMemberCard
  alias App.Repo

  @side 2400

  @doc "Sets the photo to `bytes`, or removes it for nil. `:ok` or `{:error, text}`."
  def call(%Team{} = team, %Member{team_id: team_id} = member, bytes, %User{} = user, now)
      when team_id == team.id do
    with {:ok, bytes} <- to_jpeg(bytes),
         {:ok, _d4h_member_id} <-
           ApplyEdit.call(team, user, plan(member, bytes), now, photo: bytes) do
      member = CheckMemberPhoto.store(member, bytes != nil)
      touch(member, now)
      RefreshMemberCard.resend(team, member, now)
      IssueEveryMemberCard.call(team, now)
      :ok
    end
  end

  def plan(%Member{} = member, nil) do
    %ChangeSetRow{
      action: :remove_member_photo,
      member_id: member.id,
      d4h_record_id: member.d4h_member_id,
      old_value: %{},
      new_value: %{}
    }
  end

  def plan(%Member{} = member, bytes) when is_binary(bytes) do
    %ChangeSetRow{
      action: :set_member_photo,
      member_id: member.id,
      d4h_record_id: member.d4h_member_id,
      old_value: %{},
      new_value: %{"size" => byte_size(bytes)}
    }
  end

  # Pages load the photo with `updated_at` as its version (Member.photo_version/1), and a
  # browser keeps it an hour, so this makes them load the new one at once.
  defp touch(%Member{id: id}, now) do
    Member
    |> where([m], m.id == ^id)
    |> Repo.update_all(set: [updated_at: DateTime.truncate(now, :microsecond)])
  end

  defp to_jpeg(nil), do: {:ok, nil}

  defp to_jpeg(bytes) do
    case Service.Image.jpeg(bytes, @side) do
      {:ok, jpeg} ->
        {:ok, jpeg}

      {:error, :too_many_pixels} ->
        {:error, "SAR Duty cannot read a photo this large. Select a smaller photo."}

      {:error, _reason} ->
        {:error, "SAR Duty cannot read this photo. Take another, or select one."}
    end
  end
end
