defmodule App.Operation.RefreshD4HData.Members do
  alias App.Adapter.D4H
  alias App.Model.Member

  def call(d4h, team_id) do
    d4h_members = D4H.fetch_team_members(d4h)
    Enum.each(d4h_members, fn d4h_member -> upsert_member(team_id, d4h_member) end)
    :ok
  end

  defp upsert_member(team_id, d4h_member) do
    member = Member.get_by(team_id: team_id, d4h_id: d4h_member.member_id)

    if member do
      Member.update!(member, %{
        ref_id: d4h_member.ref_id,
        name: d4h_member.name,
        email: d4h_member.email,
        phone: d4h_member.phone,
        address: d4h_member.address,
        position: d4h_member.position,
        joined_at: d4h_member.joined_at,
        left_at: d4h_member.left_at
      })
    else
      Member.insert!(%{
        team_id: team_id,
        d4h_id: d4h_member.member_id,
        ref_id: d4h_member.ref_id,
        name: d4h_member.name,
        email: d4h_member.email,
        phone: d4h_member.phone,
        address: d4h_member.address,
        position: d4h_member.position,
        joined_at: d4h_member.joined_at,
        left_at: d4h_member.left_at
      })
    end
  end
end
