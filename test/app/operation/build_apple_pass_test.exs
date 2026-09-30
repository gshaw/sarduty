defmodule App.Operation.BuildApplePassTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.BuildApplePass

  @now ~U[2026-09-30 12:00:00Z]
  @config %{pass_type_id: "pass.com.sarduty.member-card", team_id: "TEAM123"}

  defp card(attrs \\ %{}) do
    team = %Team{
      name: "Example SAR",
      timezone: "America/Vancouver",
      d4h_refreshed_at: ~U[2026-09-30 13:05:00Z]
    }

    member = %Member{name: "Alex Example", joined_at: ~U[2019-03-12 08:00:00Z], team: team}
    struct(%MemberCard{id: 7, code: "K7Q4M2XA", member: member}, attrs)
  end

  test "shows the member, their status, and how long they've been a member" do
    json = BuildApplePass.pass_json(card(), [], @config, @now)

    assert json.passTypeIdentifier == "pass.com.sarduty.member-card"
    assert json.teamIdentifier == "TEAM123"
    assert json.serialNumber == "member-card-7"
    assert json.voided == false
    assert [%{value: "Active"}] = json.generic.headerFields
    assert [%{value: "Alex Example"}] = json.generic.primaryFields

    assert [%{value: "Mar 2019"}, %{value: "8 years"}] = json.generic.secondaryFields
  end

  test "the QR code holds only the code, never a link" do
    [barcode] = BuildApplePass.pass_json(card(), [], @config, @now).barcodes

    assert barcode.format == "PKBarcodeFormatQR"
    assert barcode.message == "K7Q4M2XA"
    assert barcode.altText == "K7Q4-M2XA"
  end

  test "keeps to Apple's limit of four secondary and auxiliary fields with a square code" do
    generic = BuildApplePass.pass_json(card(), [], @config, @now).generic

    refute Map.has_key?(generic, :auxiliaryFields)
    assert length(generic.secondaryFields) <= 4
  end

  test "a cancelled card is voided" do
    json = [revoked_at: @now] |> card() |> BuildApplePass.pass_json([], @config, @now)
    assert json.voided == true
  end

  test "a member who left shows as not active" do
    card = card()
    card = put_in(card.member.left_at, ~U[2026-01-01 00:00:00Z])

    assert [%{value: "Not active"}] =
             BuildApplePass.pass_json(card, [], @config, @now).generic.headerFields
  end

  test "lists the team's picked qualifications on the back, and leaves them off when none" do
    qualifications = [
      %{name: "First Aid", status: :current, ends_at: ~U[2026-11-15 08:00:00Z]},
      %{name: "Rope", status: :not_current, ends_at: nil}
    ]

    back = BuildApplePass.pass_json(card(), qualifications, @config, @now).generic.backFields
    field = Enum.find(back, &(&1.key == "qualifications"))
    assert field.value == "First Aid — expires Nov 2026\nRope — not current"

    back = BuildApplePass.pass_json(card(), [], @config, @now).generic.backFields
    refute Enum.any?(back, &(&1.key == "qualifications"))
  end
end
