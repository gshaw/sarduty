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
    struct(%MemberCard{id: 7, code: "K7Q4M2XA", serial_number: "member-3", member: member}, attrs)
  end

  test "shows the member, their status, and how long they've been a member" do
    json = BuildApplePass.pass_json(card(), [], @config, @now)

    assert json.passTypeIdentifier == "pass.com.sarduty.member-card"
    assert json.teamIdentifier == "TEAM123"
    assert json.serialNumber == "member-3"
    assert json.voided == false
    refute Map.has_key?(json.generic, :headerFields)
    assert [%{value: "Alex Example"}] = json.generic.primaryFields

    assert [%{value: "Active"}, %{value: "Mar 2019"}, %{value: "8 years"}] =
             json.generic.secondaryFields
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

    assert [%{value: "Not active"} | _] =
             BuildApplePass.pass_json(card, [], @config, @now).generic.secondaryFields
  end

  test "lists the team's picked qualifications on the back, and leaves them off when none" do
    qualifications = [
      %{name: "First Aid", status: :current, ends_at: ~U[2026-11-15 08:00:00Z]},
      %{name: "Rope", status: :not_current, ends_at: nil}
    ]

    back = BuildApplePass.pass_json(card(), qualifications, @config, @now).generic.backFields

    assert [
             %{label: "First Aid", value: "Expires Nov 2026", changeMessage: "First Aid: %@"},
             %{label: "Rope", value: "Not current"}
           ] = Enum.filter(back, &String.starts_with?(&1.key, "qualification-"))

    back = BuildApplePass.pass_json(card(), [], @config, @now).generic.backFields
    refute Enum.any?(back, &String.starts_with?(&1.key, "qualification-"))
  end

  test "an updatable card points Wallet at the web service" do
    json =
      [authentication_token: "token-0123456789abcdef"]
      |> card()
      |> BuildApplePass.pass_json([], @config, @now)

    assert json.webServiceURL =~ "/wallet"
    assert json.authenticationToken == "token-0123456789abcdef"

    refute card() |> BuildApplePass.pass_json([], @config, @now) |> Map.has_key?(:webServiceURL)
  end

  test "a cancelled card says so" do
    json = [revoked_at: @now] |> card() |> BuildApplePass.pass_json([], @config, @now)
    assert [%{value: "Cancelled"} | _] = json.generic.secondaryFields
  end

  test "the fingerprint ignores the last-refreshed date but not the rest" do
    base = card()
    later = put_in(base.member.team.d4h_refreshed_at, ~U[2026-10-01 13:00:00Z])
    left = put_in(base.member.left_at, ~U[2026-01-01 00:00:00Z])

    fingerprint =
      &(&1 |> BuildApplePass.pass_json([], @config, @now) |> BuildApplePass.fingerprint())

    assert fingerprint.(base) == fingerprint.(later)
    refute fingerprint.(base) == fingerprint.(left)
  end
end
