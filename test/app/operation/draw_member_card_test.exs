defmodule App.Operation.DrawMemberCardTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.DrawMemberCard

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

    %MemberCard{code: @code, member: member, inserted_at: ~U[2026-10-10 18:00:00Z]}
  end

  test "the front has the team, the name, Member since, and the day the card was issued" do
    data = DrawMemberCard.card_data(card(), false)
    code = MemberCard.format_code(@code)

    assert %{
             team: "Coast Range SAR",
             name_label: nil,
             name: "Cameron Ruiz",
             member_since: "Nov 2023",
             issued: "Oct 10, 2026",
             code: ^code
           } = data
  end

  # A copy never updates, so nothing that changes goes on it: the QR code is the check.
  test "a copy shows no status, Valid until, Last updated, or endorsements" do
    data = DrawMemberCard.card_data(card(), false)

    for key <- [:status, :valid_until, :endorsements, :made], do: refute(Map.has_key?(data, key))
    refute Enum.any?(data.notes, fn [title, _body] -> title == "Last updated" end)
  end

  test "the back says how to verify the card and who issued it, with no status" do
    data = DrawMemberCard.card_data(card(), false)

    assert [
             ["How to verify this card", "Scan the QR code" <> verify],
             ["Issued by", "Coast Range Search and Rescue Society through SAR Duty."]
           ] = data.notes

    assert verify =~ "enter #{MemberCard.format_code(@code)}."
  end

  test "a team in an organization names it as issuer" do
    card = card(%{organization: %Organization{name: "Pacific Ranges SAR Association"}})
    assert [_verify, ["Issued by", issuer]] = DrawMemberCard.card_data(card, false).notes

    assert issuer ==
             "Coast Range Search and Rescue Society, a member team of Pacific Ranges SAR Association."
  end

  test "a member with no start date has no Member since (#421)" do
    card = card(%{}, %{joined_at: nil})
    assert %{member_since: nil} = DrawMemberCard.card_data(card, false)
  end

  # As its passes are (#857): a demo card can't pass for a real one.
  test "a Try a demo card says it's a sample" do
    assert %{team: "Sample card", name_label: "Sample, not real ID"} =
             DrawMemberCard.card_data(card(), true)
  end

  test "a dead card's picture says why, where its QR code goes" do
    assert %{state: nil} = DrawMemberCard.card_data(card(), false)
    assert %{state: "Replaced"} = DrawMemberCard.card_data(card(), false, :replaced)
    assert %{state: "Cancelled"} = DrawMemberCard.card_data(card(), false, :cancelled)
    assert %{state: "Not active"} = DrawMemberCard.card_data(card(), false, :inactive)
  end

  test "the printed page names whose card it is and says what to do with it" do
    data = DrawMemberCard.card_data(card(), false)
    assert data.sheet_title == "Coast Range SAR ID card · Cameron Ruiz"
    assert data.sheet_help =~ "Cut out both sides on the dashed lines."
    assert data.sheet_help =~ "the size of a plastic ID card"
  end
end
