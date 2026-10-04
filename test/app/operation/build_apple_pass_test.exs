defmodule App.Operation.BuildApplePassTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.BuildApplePass

  @now ~U[2026-09-30 12:00:00Z]
  @config %{pass_type_id: "pass.com.sarduty.member-card", team_id: "TEAM123"}

  defp card(attrs \\ %{}) do
    team = %Team{
      name: "Example SAR",
      timezone: "America/Vancouver",
      d4h_refreshed_at: ~U[2026-09-30 13:05:00Z],
      organization: nil
    }

    member = %Member{name: "Alex Example", joined_at: ~U[2019-03-12 08:00:00Z], team: team}
    struct(%MemberCard{id: 7, code: "K7Q4M2XA", serial_number: "member-3", member: member}, attrs)
  end

  test "shows the member, their status, and how long the card is good for" do
    json = BuildApplePass.pass_json(card(), [], @config, @now)

    assert json.passTypeIdentifier == "pass.com.sarduty.member-card"
    assert json.teamIdentifier == "TEAM123"
    assert json.serialNumber == "member-3"
    assert json.voided == false
    refute Map.has_key?(json.generic, :headerFields)
    assert [%{value: "Alex Example"}] = json.generic.primaryFields

    assert [
             %{label: "Status", value: "Active"},
             %{label: "Member since", value: "Mar 2019"},
             %{label: "Valid until", value: "Dec 2026"} = valid_until
           ] = json.generic.secondaryFields

    refute Map.has_key?(valid_until, :changeMessage)
    assert json.expirationDate == "2027-01-01T06:59:59Z"
  end

  test "an inactive card doesn't say how long it's good for, but still expires" do
    card = card()
    card = put_in(card.member.left_at, ~U[2026-01-01 00:00:00Z])
    json = BuildApplePass.pass_json(card, [], @config, @now)

    refute Enum.any?(json.generic.secondaryFields, &(&1.key == "valid-until"))
    assert json.expirationDate == "2027-01-01T06:59:59Z"
  end

  test "a team that has never refreshed sets no expiry" do
    card = card()
    card = put_in(card.member.team.d4h_refreshed_at, nil)
    json = BuildApplePass.pass_json(card, [], @config, @now)

    refute Map.has_key?(json, :expirationDate)
    refute Enum.any?(json.generic.secondaryFields, &(&1.key == "valid-until"))
  end

  test "the QR code opens the card's page on the verify site, with only the code printed under it" do
    [barcode] = BuildApplePass.pass_json(card(), [], @config, @now).barcodes

    assert barcode.format == "PKBarcodeFormatQR"
    assert barcode.message =~ ~r{^HTTPS?://VERIFY\.[A-Z0-9.:]+/K7Q4-M2XA$}
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
      %{name: "First Aid", ends_at: ~U[2026-11-15 08:00:00Z]},
      %{name: "Rope", ends_at: nil}
    ]

    back = BuildApplePass.pass_json(card(), qualifications, @config, @now).generic.backFields

    assert [
             %{label: "First Aid", value: "Nov 2026", changeMessage: "First Aid: %@"},
             %{label: "Rope", value: ""}
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

  test "a cancelled card says so and shows no QR code" do
    json = [revoked_at: @now] |> card() |> BuildApplePass.pass_json([], @config, @now)
    assert [%{value: "Cancelled"} | _] = json.generic.secondaryFields
    assert [%{label: "Card cancelled", value: "Alex Example"}] = json.generic.primaryFields
    refute Map.has_key?(json, :barcodes)
  end

  test "a member who left gets no QR code either" do
    card = card()
    card = put_in(card.member.left_at, ~U[2026-01-01 00:00:00Z])
    json = BuildApplePass.pass_json(card, [], @config, @now)

    assert [%{label: "Not an active member"}] = json.generic.primaryFields
    refute Map.has_key?(json, :barcodes)
  end

  test "the fingerprint ignores the last-refreshed date until valid until moves" do
    base = card()
    later = put_in(base.member.team.d4h_refreshed_at, ~U[2026-10-01 05:00:00Z])
    next_month = put_in(base.member.team.d4h_refreshed_at, ~U[2026-10-01 13:00:00Z])
    left = put_in(base.member.left_at, ~U[2026-01-01 00:00:00Z])

    fingerprint =
      &(&1 |> BuildApplePass.pass_json([], @config, @now) |> BuildApplePass.fingerprint())

    assert fingerprint.(base) == fingerprint.(later)
    refute fingerprint.(base) == fingerprint.(next_month)
    refute fingerprint.(base) == fingerprint.(left)
  end

  test "a test update adds a back field with a notice, and changes nothing else" do
    card = card(authentication_token: "token-0123456789abcdef")
    tested = card(authentication_token: "token-0123456789abcdef", pass_test_at: @now)
    json = BuildApplePass.pass_json(card, [], @config, @now)
    tested_json = BuildApplePass.pass_json(tested, [], @config, @now)

    refute Enum.any?(json.generic.backFields, &(&1.key == "test"))

    assert %{label: "Test update", value: "Sep 30, 05:00:00"} =
             test_field = Enum.find(tested_json.generic.backFields, &(&1.key == "test"))

    assert test_field.changeMessage == "SAR Duty test update %@"
    assert tested_json.authenticationToken == json.authenticationToken
    assert tested_json.serialNumber == json.serialNumber
    assert tested_json.barcodes == json.barcodes
    assert BuildApplePass.fingerprint(tested_json) == BuildApplePass.fingerprint(json)
  end

  test "a team in an organization names it as issuer, and SAR Duty nowhere" do
    card = card(authentication_token: "token-0123456789abcdef", pass_test_at: @now)
    organization = %Organization{name: "BC Search and Rescue Association"}
    card = put_in(card.member.team.organization, organization)
    json = BuildApplePass.pass_json(card, [], @config, @now)

    issuer = Enum.find(json.generic.backFields, &(&1.key == "issuer"))
    assert issuer.value =~ "Example SAR, a member team of BC Search and Rescue Association."
    refute Jason.encode!(json) =~ "SAR Duty"
  end
end
