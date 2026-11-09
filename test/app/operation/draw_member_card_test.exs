defmodule App.Operation.DrawMemberCardTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.DrawMemberCard

  @now ~U[2026-11-08 18:00:00Z]
  @code MemberCard.generate_code()

  defp card(team_attrs \\ %{}, member_attrs \\ %{}) do
    team =
      struct(
        %Team{
          name: "Coast Range SAR",
          legal_name: "Coast Range Search and Rescue Society",
          timezone: "America/Vancouver",
          d4h_refreshed_at: ~U[2026-11-08 17:50:00Z],
          organization: nil
        },
        team_attrs
      )

    member =
      struct(
        %Member{name: "Cameron Ruiz", joined_at: ~U[2023-11-14 18:00:00Z], team: team},
        member_attrs
      )

    %MemberCard{code: @code, member: member}
  end

  @endorsements [
    %{name: "First aid", ends_at: ~U[2026-11-23 08:00:00Z]},
    %{name: "Ground search and rescue", ends_at: nil}
  ]

  test "the front has the pass's front, with the day it was drawn in place of Valid until" do
    data = DrawMemberCard.card_data(card(), @endorsements, false, @now)
    code = MemberCard.format_code(@code)

    assert %{
             team: "Coast Range SAR",
             name_label: "Member",
             name: "Cameron Ruiz",
             status: "Active",
             member_since: "Nov 2023",
             code: code,
             made: "Nov 8, 2026 · Scan the code to check it"
           } = data

    refute Map.has_key?(data, :valid_until)
  end

  test "the back has each endorsement and when it expires, then what the pass's back has" do
    data = DrawMemberCard.card_data(card(), @endorsements, false, @now)

    assert data.endorsements == [
             %{name: "First aid", expires: "Expires Nov 2026"},
             %{name: "Ground search and rescue", expires: "No expiry"}
           ]

    assert [
             ["How to verify this card", "Scan the QR code" <> verify],
             ["Last updated", "November 8, 2026"],
             ["Issued by", "Coast Range Search and Rescue Society through SAR Duty." <> _]
           ] = data.notes

    assert verify =~ "enter #{MemberCard.format_code(@code)}."
  end

  test "a member with no start date has no Member since (#421)" do
    card = card(%{}, %{joined_at: nil})
    assert %{member_since: nil} = DrawMemberCard.card_data(card, [], false, @now)
  end

  test "a team never refreshed says so" do
    card = card(%{d4h_refreshed_at: nil})
    data = DrawMemberCard.card_data(card, [], false, @now)
    assert ["Last updated", "Never"] in data.notes
  end

  # As its passes are (#857): a demo card can't pass for a real one.
  test "a Try a demo card says it's a sample" do
    assert %{team: "Sample card", name_label: "Sample, not real ID"} =
             DrawMemberCard.card_data(card(), [], true, @now)
  end

  test "the printed page names whose card it is and says what to do with it" do
    data = DrawMemberCard.card_data(card(), [], false, @now)
    assert data.sheet_title == "Coast Range SAR ID card · Cameron Ruiz"
    assert data.sheet_help =~ "Cut out both sides on the dashed lines."
  end
end
