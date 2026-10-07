defmodule App.Operation.CreateTaxCreditLetterTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.CreateTaxCreditLetter

  @team %Team{
    name: "North Shore Rescue",
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
      tags: tags
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
    assert letter.letter_content =~ "Primary Hours: 3 hours, 30 minutes"
    assert letter.letter_content =~ "Secondary Hours: 1 hour\n"
    assert letter.letter_content =~ "Total Hours: 4 hours, 30 minutes"
    assert letter.letter_content =~ "Certified on January 15, 2026."
    assert letter.letter_content =~ "Pat Lee"
    assert letter.letter_content =~ "Reference: SRVTC-ABCDE"
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

    test "without a signer, the team's name signs" do
      team = %{@team | authorized_by_name: nil}
      assert CreateTaxCreditLetter.signer_block(team) == "North Shore Rescue"
    end
  end
end
