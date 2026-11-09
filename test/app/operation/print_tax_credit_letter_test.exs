# cspell:ignore Łukasz Nowak Nguyễn Văn -- names past WinAnsi (#917)
defmodule App.Operation.PrintTaxCreditLetterTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Operation.CreateTaxCreditLetter
  alias App.Operation.PrintTaxCreditLetter
  alias App.Operation.SaveTeamSignature

  setup do
    team = team_fixture()
    %{team: team, member: member_fixture(team)}
  end

  defp create(team, member),
    do: CreateTaxCreditLetter.call(team: Repo.reload!(team), member_id: member.id, year: 2025)

  defp print(letter) do
    letter = Repo.preload(letter, [:pdf, member: :team], force: true)
    {:ok, printed} = PrintTaxCreditLetter.call(letter, letter.pdf.code)
    printed.attachment
  end

  # Pictures on the page. A picture with an alpha channel stores it as a second image,
  # its /SMask. PDFLock encrypts strings and streams, so the dictionaries still read.
  defp images(%{content: pdf}), do: count(pdf, "/Subtype/Image") - count(pdf, "/SMask")

  defp count(content, pattern), do: length(String.split(content, pattern)) - 1

  test "prints a name past Western European letters (#917)", %{team: team} do
    for name <- ["Łukasz Nowak", "Nguyễn Văn An"] do
      letter = create(team, member_fixture(team, %{name: name}))

      assert letter.letter_content =~ "Name: #{name}\n"
      assert %{content: "%PDF" <> _rest} = print(letter)
    end
  end

  test "titles the PDF and locks it print-only", %{team: team, member: member} do
    attachment = team |> create(member) |> print()

    assert attachment.title == "2025 SRVTC #{team.legal_name}"
    assert attachment.filename =~ ~r/^2025_SRVTC_.*\.pdf$/
    assert attachment.content =~ "/Encrypt"
    assert {:ok, _key} = Service.PDFLock.file_key(attachment.content)
  end

  test "prints the letter's own hours and date, not attendance now", %{member: member} do
    letter =
      member
      |> tax_credit_letter_fixture(%{year: 2024, primary_minutes: 600, secondary_minutes: 30})
      |> Map.put(:inserted_at, ~U[2025-01-20 18:00:00Z])
      |> Repo.preload(member: :team)

    read = PrintTaxCreditLetter.read(letter.member.team, member.id, 2024, letter.inserted_at)
    output = PrintTaxCreditLetter.output(letter, "K7Q4M2XA9HVB3TN", read)
    text = App.Document.text(output, "letter")

    assert text =~ "in 2024."
    assert text =~ "Primary Hours: 10 hours\nSecondary Hours: 30 min\nTotal Hours: 10h 30m\n"
    assert text =~ "Certified on January 20, 2025."

    # Its verify page shows the same hours (#970).
    assert %{"label" => "Total hours", "text" => "10h 30m"} in output.shows
    assert %{"label" => "Name", "text" => member.name} in output.shows
  end

  describe "the letterhead" do
    test "a team without a logo gets none, not SAR Duty's", %{team: team, member: member} do
      assert team |> create(member) |> print() |> images() == 0
    end

    test "prints the team's logo, padded square", %{team: team, member: member} do
      team_logo_fixture(team, png_fixture(1500, 1740))
      assert team |> create(member) |> print() |> images() == 1
    end

    test "puts the organization's logo beside the team's", %{team: team, member: member} do
      organization_fixture([team])
      team_logo_fixture(team, png_fixture(300, 150))
      assert team |> create(member) |> print() |> images() == 2
    end

    test "leaves out the organization's when it has none", %{team: team, member: member} do
      organization_fixture([team], %{logo: nil})
      assert team |> create(member) |> print() |> images() == 0
    end
  end

  describe "the signature" do
    test "prints the team's signature", %{team: team, member: member} do
      {:ok, _team} = SaveTeamSignature.call(team, png_fixture(600, 150))
      letter = create(team, member)

      assert images(print(letter)) == 1
      # The picture takes the place of the blank lines left to sign in.
      refute letter.letter_content =~ "\n\n\n\n"
    end

    test "leaves room to sign without one", %{team: team, member: member} do
      letter = create(team, member)

      assert images(print(letter)) == 0
      assert letter.letter_content =~ ~r/Certified on .*\.\n\n\n\n\n#{team.legal_name}/
    end
  end

  test "prints the verify code of the ID it's published under (#970)", %{member: member} do
    letter = member |> tax_credit_letter_fixture() |> Repo.preload(member: :team)
    {:ok, printed} = PrintTaxCreditLetter.call(letter, "K7Q4M2XA9HVB3TN")

    assert printed.code == "K7Q4M2XA9HVB3TN"
    assert printed.name == "Tax credit letter"
    assert %{content: "%PDF" <> _rest} = printed.attachment
  end

  test "a Try a demo team's letter says SAMPLE across it (#857)", %{team: team, member: member} do
    real = team |> create(member) |> print()
    demo_team_fixture(team)
    sample = team |> create(member_fixture(team)) |> print()

    assert images(real) == 0
    assert images(sample) == 1
  end
end
