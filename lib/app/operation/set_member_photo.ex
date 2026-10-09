defmodule App.Operation.SetMemberPhoto do
  @moduledoc """
  A team admin sets or removes the photo of a member of a team on SAR Duty Records
  (docs/records.md). One change set row through App.Operation.ApplyEdit. The row says
  only that the photo changed: the image goes to Records and is never kept here. Then
  the member's Apple Wallet pass is nudged, so the phone fetches the new photo.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Operation.PushPassUpdates

  @doc "Sets the photo to `bytes`, or removes it for nil. `:ok` or `{:error, text}`."
  def call(%Team{} = team, %Member{team_id: team_id} = member, bytes, %User{} = user, now)
      when team_id == team.id do
    with {:ok, _d4h_member_id} <-
           ApplyEdit.call(team, user, plan(member, bytes), now, photo: bytes) do
      team |> MemberCard.find_current(member) |> List.wrap() |> PushPassUpdates.push_cards()
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
