defmodule App.Operation.PublishTaxCreditLetterTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.PrintTaxCreditLetter
  alias App.Operation.PublishTaxCreditLetter

  # The wording's own worked examples are the expect lines in
  # priv/documents/tax_credit_letter.txt; these check what the letter reads.

  setup do
    team =
      %{legal_name: "North Shore Rescue"}
      |> team_fixture()
      |> Ecto.Changeset.change(authorized_by_name: "Pat Lee", signature: png_fixture(600, 150))
      |> Repo.update!()

    %{team: team, member: member_fixture(team, %{name: "Sam Doe", address: "1 Elm St"})}
  end

  # A letter published with nobody publishing it.
  defp create(team, member, current_id \\ nil) do
    {:ok, prepared} = PublishTaxCreditLetter.prepare(team, member.id, 2025, nil)
    PublishTaxCreditLetter.insert!(prepared, current_id)
  end

  # What the letter says, as it prints now.
  defp text(team, member) do
    read = PrintTaxCreditLetter.read(team, member.id, 2025, DateTime.utc_now())
    PrintTaxCreditLetter.text(team, read)
  end

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

    assert {letter.member_id, letter.year, letter.subject} ==
             {member.id, 2025, "member:#{member.id}:2025"}

    assert PublishedPDF.parse_code(letter.code)
    assert TaxCreditLetter.minutes(letter) == {210, 60}
    assert %{"label" => "Total hours", "text" => "4h 30m"} in letter.shows
    assert "%PDF" <> _ = PublishedPDF.attachment(letter).content

    text = text(team, member)
    assert text =~ "Primary Hours: 3h 30m\nSecondary Hours: 1 hour\n"
    assert text =~ "Total Hours: 4h 30m\n"
    # The verify code prints the ID, so the text has no reference line (#970).
    refute text =~ "Reference"
  end

  test "a member with no hours gets a letter that says 0 hours", %{team: team, member: member} do
    letter = create(team, member)

    assert TaxCreditLetter.minutes(letter) == {0, 0}
    assert text(team, member) =~ "Total Hours: 0 hours"
  end

  test "prints the member's address, and leaves the line out when D4H has none",
       %{team: team, member: member} do
    assert text(team, member) =~ "Name: Sam Doe\nAddress: 1 Elm St\n"

    for address <- [nil, ""] do
      text = text(team, member_fixture(team, %{name: "Lee Park", address: address}))

      assert text =~ "Name: Lee Park\n\n"
      refute text =~ "Address:"
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

    assert text(team, member) =~ ~r/Pat Lee\nPresident\npresident@example.com\z/
  end

  test "without a signer, the team's legal name signs", %{team: team, member: member} do
    team =
      team |> Ecto.Changeset.change(authorized_by_name: nil, signature: nil) |> Repo.update!()

    assert text(team, member) =~ ~r/\n\n\n\n\nNorth Shore Rescue\z/
  end

  describe "publishing again (#970)" do
    test "prints a new one with a new ID; the old one stays, Replaced", %{
      team: team,
      member: member
    } do
      old = create(team, member)
      new = create(team, member, old.id)

      assert new.code != old.code
      assert old |> Repo.reload!() |> PublishedPDF.status() == :replaced
      assert TaxCreditLetter.get_current(member, 2025).id == new.id
    end

    test "refuses when another took its place meanwhile", %{team: team, member: member} do
      old = create(team, member)
      _other = create(team, member, old.id)

      {:ok, prepared} = PublishTaxCreditLetter.prepare(team, member.id, 2025, nil)
      assert PublishTaxCreditLetter.insert(prepared, old.id) == {:error, :stale}
    end
  end

  # What the letter needs blocks publishing, never a draft (#995).
  test "refuses while a value the letter needs is blank, and prints nothing",
       %{team: team, member: member} do
    team = team |> Ecto.Changeset.change(signature: nil) |> Repo.update!()

    assert PublishTaxCreditLetter.prepare(team, member.id, 2025, nil) ==
             {:error, "This letter cannot be published without the signer's signature."}

    team = team |> Ecto.Changeset.change(mailing_address: nil) |> Repo.update!()
    user = App.AccountsFixtures.user_fixture()

    assert PublishTaxCreditLetter.call(team, member.id, 2025, user, nil) ==
             {:error,
              "This letter cannot be published without 2 values: mailing address and signer's signature."}

    assert TaxCreditLetter.get_current(member, 2025) == nil
  end
end
