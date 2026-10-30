defmodule App.Operation.CreateTaxCreditLetterTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Operation.CreateTaxCreditLetter

  @team %Team{
    name: "NSR",
    legal_name: "North Shore Rescue",
    mailing_address: "123 Main St",
    timezone: "America/Vancouver",
    authorized_by_name: "Pat Lee"
  }
  @member %Member{id: 7, name: "Sam Doe", address: "1 Elm St"}
  @now ~U[2026-01-15 18:00:00Z]

  defp row(started_at, finished_at, tags) do
    %{
      member_id: 7,
      started_at: started_at,
      finished_at: finished_at,
      duration_in_minutes: 0,
      tags: tags,
      chore: false
    }
  end

  test "prints the member's counted hours" do
    rows = [
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 20:30:00Z], ["Primary Hours"]),
      # Overlaps the first by an hour, so it adds 1 hour of secondary.
      row(~U[2025-03-01 19:30:00Z], ~U[2025-03-01 21:30:00Z], ["Secondary Hours"]),
      # Another member's row.
      %{row(~U[2025-03-02 17:00:00Z], ~U[2025-03-02 20:00:00Z], ["Primary Hours"]) | member_id: 8}
    ]

    letter =
      CreateTaxCreditLetter.plan(
        @team,
        @member,
        rows,
        2025,
        "SRVTC-ABCDE",
        ~U[2026-01-15 18:00:00Z]
      )

    assert letter.member_id == 7
    assert letter.year == 2025
    assert letter.ref_id == "SRVTC-ABCDE"
    assert {letter.primary_minutes, letter.secondary_minutes} == {210, 60}
    assert letter.letter_content =~ "Primary Hours: 3h 30m\n"
    assert letter.letter_content =~ "Secondary Hours: 1 hour\n"
    assert letter.letter_content =~ "Total Hours: 4h 30m\n"
    assert letter.letter_content =~ "Certified on January 15, 2026."
    assert letter.letter_content =~ "Pat Lee"

    assert letter.letter_content =~
             "Reference: SRVTC-ABCDE\nVerify this letter at verify.sarduty.com/letters\n"
  end

  test "a member with no hours gets a letter that says 0 hours" do
    letter =
      CreateTaxCreditLetter.plan(
        @team,
        @member,
        [],
        2025,
        "SRVTC-ABCDE",
        ~U[2026-01-15 18:00:00Z]
      )

    assert letter.letter_content =~ "Total Hours: 0 hours"
  end

  test "prints hours as the letters table shows them, and reads them back" do
    rows = [
      row(~U[2025-03-01 17:00:00Z], ~U[2025-03-01 17:45:00Z], ["Primary Hours"]),
      row(~U[2025-03-02 17:00:00Z], ~U[2025-03-02 19:00:00Z], ["Secondary Hours"])
    ]

    letter = CreateTaxCreditLetter.plan(@team, @member, rows, 2025, "SRVTC-ABCDE", @now)

    assert letter.letter_content =~ "Primary Hours: 45 min\n"
    assert letter.letter_content =~ "Secondary Hours: 2 hours\n"
    assert letter.letter_content =~ "Total Hours: 2h 45m\n"
    assert TaxCreditLetter.parse_minutes(letter.letter_content) == {45, 120}
  end

  test "names the member, the year, and the Act, and says where the hours come from" do
    letter = CreateTaxCreditLetter.plan(@team, @member, [], 2025, "SRVTC-ABCDE", @now)

    assert letter.letter_content =~
             "Sam Doe volunteered with North Shore Rescue in 2025. North Shore Rescue is an eligible search and rescue organization under subsection 118.07(1) of the Income Tax Act."

    assert letter.letter_content =~
             "These hours come from North Shore Rescue's attendance records."
  end

  test "prints the member's address, and leaves the line out when D4H has none" do
    letter = CreateTaxCreditLetter.plan(@team, @member, [], 2025, "SRVTC-ABCDE", @now)
    assert letter.letter_content =~ "Name: Sam Doe\nAddress: 1 Elm St\n"

    for address <- [nil, ""] do
      member = %{@member | address: address}
      letter = CreateTaxCreditLetter.plan(@team, member, [], 2025, "SRVTC-ABCDE", @now)
      assert letter.letter_content =~ "Name: Sam Doe\n\n"
      refute letter.letter_content =~ "Address:"
    end
  end

  describe "the contact line" do
    test "points to the signer's details when they have a phone or email" do
      team = %{@team | authorized_by_email: "president@example.com"}
      letter = CreateTaxCreditLetter.plan(team, @member, [], 2025, "SRVTC-ABCDE", @now)
      assert letter.letter_content =~ "If you have questions, contact me using the details below."
    end

    test "names the team when the signer has neither" do
      team = %{@team | authorized_by_phone: ""}
      letter = CreateTaxCreditLetter.plan(team, @member, [], 2025, "SRVTC-ABCDE", @now)
      assert letter.letter_content =~ "If you have questions, contact North Shore Rescue."
    end
  end

  describe "the signer block" do
    test "prints the signer's title, phone, and email under their name" do
      team = %{
        @team
        | authorized_by_title: "President",
          authorized_by_phone: "604-555-0100",
          authorized_by_email: "president@example.com"
      }

      letter = CreateTaxCreditLetter.plan(team, @member, [], 2025, "SRVTC-ABCDE", @now)

      assert letter.letter_content =~
               "Pat Lee\nPresident\n604-555-0100\npresident@example.com\n\nReference: SRVTC-ABCDE"
    end

    test "leaves out what the team left empty" do
      team = %{@team | authorized_by_title: "President", authorized_by_phone: ""}
      letter = CreateTaxCreditLetter.plan(team, @member, [], 2025, "SRVTC-ABCDE", @now)
      assert letter.letter_content =~ "Pat Lee\nPresident\n\nReference: SRVTC-ABCDE"
    end

    test "copies the team's signature onto the letter" do
      team = %{@team | signature: "png bytes"}

      assert CreateTaxCreditLetter.plan(team, @member, [], 2025, "SRVTC-ABCDE", @now).signature ==
               "png bytes"

      assert CreateTaxCreditLetter.plan(@team, @member, [], 2025, "SRVTC-ABCDE", @now).signature ==
               nil
    end

    test "leaves the gap the signature goes in, between the closing and the name" do
      letter = CreateTaxCreditLetter.plan(@team, @member, [], 2025, "SRVTC-ABCDE", @now)

      assert {body, signer} = TaxCreditLetter.split_at_signature(letter.letter_content)
      assert body =~ ~r/Certified on January 15, 2026\.$/
      assert signer =~ ~r/^Pat Lee\n/
    end

    test "without a signer, the team's legal name signs" do
      team = %{@team | authorized_by_name: nil}
      assert CreateTaxCreditLetter.signer_block(team) == "North Shore Rescue"
    end
  end
end
