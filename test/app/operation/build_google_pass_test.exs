defmodule App.Operation.BuildGooglePassTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.BuildGooglePass

  @now ~U[2026-09-30 12:00:00Z]
  @config %{issuer_id: "3388", host: "sarduty.com", images: true}

  defp card(attrs \\ %{}) do
    team = %Team{
      name: "Example SAR",
      subdomain: "example",
      timezone: "America/Vancouver",
      d4h_refreshed_at: ~U[2026-09-30 13:05:00Z]
    }

    member = %Member{name: "Alex Example", joined_at: ~U[2019-03-12 08:00:00Z], team: team}
    struct(%MemberCard{id: 7, code: "K7Q4M2XA", member: member}, attrs)
  end

  defp object(card, qualifications \\ []),
    do: BuildGooglePass.pass_object(card, qualifications, @config, @now)

  defp text(object, id), do: Enum.find(object.textModulesData, &(&1.id == id))

  test "shows the team, the member, their status, and how long the card is good for" do
    object = object(card())

    assert object.id == "3388.sarduty.com-card-7"
    assert object.classId == "3388.sarduty.com-member-card"
    assert object.state == "ACTIVE"
    assert object.cardTitle.defaultValue.value == "Example SAR"
    assert object.header.defaultValue.value == "Alex Example"
    assert object.subheader.defaultValue.value == "Member"
    assert text(object, "status").body == "Active"
    assert text(object, "member_since").body == "Mar 2019"
    assert text(object, "valid_until").body == "Dec 2026"
    refute text(object, "member_for")
    assert object.validTimeInterval == %{end: %{date: "2027-01-01T06:59:59Z"}}
  end

  test "an inactive card doesn't say how long it's good for, but still expires" do
    card = card()
    object = object(put_in(card.member.left_at, ~U[2026-01-01 00:00:00Z]))

    refute text(object, "valid_until")
    assert object.validTimeInterval
  end

  test "the class puts every field its front row names on the object" do
    class = BuildGooglePass.pass_class(@config)
    [row] = class.classTemplateInfo.cardTemplateOverride.cardRowTemplateInfos
    ids = Enum.map(object(card()).textModulesData, & &1.id)

    for {_item, %{firstValue: %{fields: [%{fieldPath: path}]}}} <- row.threeItems do
      [_, id] = Regex.run(~r/textModulesData\['(\w+)'\]/, path)
      assert id in ids
    end
  end

  test "the QR code opens the card's page on the verify site, with only the code printed under it" do
    barcode = object(card()).barcode

    assert barcode.type == "QR_CODE"
    assert barcode.value =~ ~r{^HTTPS?://VERIFY\.[A-Z0-9.:]+/K7Q4-M2XA$}
    assert barcode.alternateText == "K7Q4-M2XA"
  end

  test "the team logo is by the name, the photo is under the code, and dev has neither" do
    object = object(card())
    assert object.logo.sourceUri.uri =~ "/teams/example/logo"
    assert object.heroImage.sourceUri.uri =~ "/verify/K7Q4M2XA/banner"

    dev = BuildGooglePass.pass_object(card(), [], %{@config | images: false}, @now)
    refute Map.has_key?(dev, :logo)
    refute Map.has_key?(dev, :heroImage)
  end

  test "a cancelled card expires and shows no QR code or photo" do
    object = object(card(revoked_at: @now))

    assert object.state == "EXPIRED"
    assert object.subheader.defaultValue.value == "Card cancelled"
    assert text(object, "status").body == "Cancelled"
    refute Map.has_key?(object, :barcode)
    refute Map.has_key?(object, :heroImage)
  end

  test "a member who left stays a live pass but shows as not active, with no QR code" do
    card = card()
    object = object(put_in(card.member.left_at, ~U[2026-01-01 00:00:00Z]))

    assert object.state == "ACTIVE"
    assert object.subheader.defaultValue.value == "Not an active member"
    refute Map.has_key?(object, :barcode)
  end

  test "lists the team's picked qualifications" do
    qualifications = [
      %{name: "First Aid", status: :current, ends_at: ~U[2026-11-15 08:00:00Z]},
      %{name: "Rope", status: :not_current, ends_at: nil}
    ]

    object = object(card(), qualifications)

    assert %{header: "First Aid", body: "Expires Nov 2026"} = text(object, "qualification_0")
    assert %{header: "Rope", body: "Not current"} = text(object, "qualification_1")
  end

  test "the fingerprint ignores the last-refreshed date until valid until moves" do
    base = card()
    later = put_in(base.member.team.d4h_refreshed_at, ~U[2026-10-01 05:00:00Z])
    next_month = put_in(base.member.team.d4h_refreshed_at, ~U[2026-10-01 13:00:00Z])
    left = put_in(base.member.left_at, ~U[2026-01-01 00:00:00Z])
    fingerprint = &(&1 |> object() |> BuildGooglePass.fingerprint())

    assert fingerprint.(base) == fingerprint.(later)
    refute fingerprint.(base) == fingerprint.(next_month)
    refute fingerprint.(base) == fingerprint.(left)
  end
end
