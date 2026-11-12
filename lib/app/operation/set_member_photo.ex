defmodule App.Operation.SetMemberPhoto do
  @moduledoc """
  A team admin sets a member's photo, on any team (#1028), or removes it on a team on SAR
  Duty Records (docs/records.md): D4H has no way to remove one. One change set row
  through App.Operation.ApplyEdit. The row says only that the photo changed: the image
  goes to the team's records and is never kept here. Then `has_photo` is set with no
  download, the member's card goes to their phones again (RefreshMemberCard), and Every
  member gets a card makes theirs the moment a first photo is saved (#1012). A photo
  removed leaves a card already out.

  `bytes` is the photo as it goes: Add a photo's JPEG, from Service.MemberPhoto.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.PhotoAsk
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Operation.CheckMemberPhoto
  alias App.Operation.IssueEveryMemberCard
  alias App.Operation.RefreshMemberCard

  @doc "Sets the photo to `bytes`, or removes it for nil. `:ok` or `{:error, text}`."
  def call(%Team{} = team, %Member{team_id: team_id} = member, bytes, %User{} = user, now)
      when team_id == team.id do
    with {:ok, _d4h_member_id} <-
           ApplyEdit.call(team, user, plan(member, bytes), now, photo: bytes) do
      member = CheckMemberPhoto.store(member, bytes != nil, now)
      # A photo set answers a team admin's ask for one (#1030).
      if bytes, do: PhotoAsk.close_for_member(member, now)
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
end
