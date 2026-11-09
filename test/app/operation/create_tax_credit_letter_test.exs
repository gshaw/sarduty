defmodule App.Operation.CreateTaxCreditLetterTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.TaxCreditLetter
  alias App.Operation.CreateTaxCreditLetter

  # The wording's own worked examples are the expect lines in
  # priv/documents/tax_credit_letter.txt; these check what the letter reads.

  setup do
    team =
      %{legal_name: "North Shore Rescue"}
      |> team_fixture()
      |> Ecto.Changeset.change(authorized_by_name: "Pat Lee")
      |> Repo.update!()

    %{team: team, member: member_fixture(team, %{name: "Sam Doe", address: "1 Elm St"})}
  end

  defp create(team, member),
    do: CreateTaxCreditLetter.call(team: team, member_id: member.id, year: 2025)

  test "prints and keeps the member's counted hours", %{team: team, member: member} do
    primary =
      activity_fixture(team, %{
        started_at: ~U[2025-03-01 17:00:00Z],
        finished_at: ~U[2025-03-01 20:30:00Z]
      })

    # Overlaps the first by an hour, so it adds 1 hour of secondary.
    secondary =
      activity_fixture(team, %{
        tags: ["Secondary Hours"],
        started_at: ~U[2025-03-01 19:30:00Z],
        finished_at: ~U[2025-03-01 21:30:00Z]
      })

    attendance_fixture(primary, member)
    attendance_fixture(secondary, member)
    # Another member's.
    attendance_fixture(primary, member_fixture(team))

    letter = create(team, member)

    assert {letter.member_id, letter.year} == {member.id, 2025}
    assert {:code, _code} = App.Model.PublishedPDF.parse_code(letter.pdf.code)
    assert {letter.primary_minutes, letter.secondary_minutes} == {210, 60}
    assert letter.letter_content =~ "Primary Hours: 3h 30m\nSecondary Hours: 1 hour\n"
    assert letter.letter_content =~ "Total Hours: 4h 30m\n"
    assert TaxCreditLetter.parse_minutes(letter.letter_content) == {210, 60}

    # The verify code prints the ID, so the text has no reference line (#970).
    refute letter.letter_content =~ "Reference"
  end

  test "a member with no hours gets a letter that says 0 hours", %{team: team, member: member} do
    letter = create(team, member)

    assert {letter.primary_minutes, letter.secondary_minutes} == {0, 0}
    assert letter.letter_content =~ "Total Hours: 0 hours"
  end

  test "prints the member's address, and leaves the line out when D4H has none",
       %{team: team, member: member} do
    assert create(team, member).letter_content =~ "Name: Sam Doe\nAddress: 1 Elm St\n"

    for address <- [nil, ""] do
      member = member_fixture(team, %{name: "Lee Park", address: address})
      letter = create(team, member)

      assert letter.letter_content =~ "Name: Lee Park\n\n"
      refute letter.letter_content =~ "Address:"
    end
  end

  test "prints the signer's title, phone, and email under their name, leaving out the empty",
       %{team: team, member: member} do
    team =
      team
      |> Ecto.Changeset.change(
        authorized_by_title: "President",
        authorized_by_phone: "",
        authorized_by_email: "president@example.com"
      )
      |> Repo.update!()

    assert create(team, member).letter_content =~ ~r/Pat Lee\nPresident\npresident@example.com\z/
  end

  test "without a signer, the team's legal name signs", %{team: team, member: member} do
    team = team |> Ecto.Changeset.change(authorized_by_name: nil) |> Repo.update!()

    assert create(team, member).letter_content =~ ~r/\n\n\n\n\nNorth Shore Rescue\z/
  end
end
