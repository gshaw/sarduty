# cspell:ignore Łukasz Nowak -- a Polish name, past WinAnsi (#917)
defmodule App.Operation.SaveTaxCreditLetterPDFTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.LetterPDF
  alias App.Model.LetterPDFFile
  alias App.Model.TaxCreditLetter
  alias App.Operation.CreateTaxCreditLetter
  alias App.Operation.DeleteTaxCreditLetter
  alias App.Operation.LoadTaxCreditLetterPDF
  alias App.Operation.ReplaceTaxCreditLetter

  # Ł is past WinAnsi, which is all the pdf package writes (#917).
  @past_win_ansi "Łukasz Nowak"

  setup do
    team = team_fixture()
    %{team: team, member: member_fixture(team)}
  end

  defp create(team, member),
    do: CreateTaxCreditLetter.call(team: team, member_id: member.id, year: 2025)

  describe "making a letter" do
    test "saves its PDF", %{team: team, member: member} do
      letter = create(team, member)

      assert %{content: "%PDF" <> _rest, title: "2025 SRVTC " <> _name} =
               LetterPDF.attachment(letter)
    end

    test "with a name past WinAnsi makes the letter without one (#917)", %{team: team} do
      member = member_fixture(team, %{name: @past_win_ansi})
      letter = create(team, member)

      assert letter.letter_content =~ @past_win_ansi
      assert LetterPDF.attachment(letter) == nil
    end
  end

  describe "downloading or emailing" do
    test "serves the saved file, not one drawn with the team's logo now",
         %{team: team, member: member} do
      letter = create(team, member)
      saved = LetterPDF.attachment(letter).content
      team_logo_fixture(team, png_fixture(300, 150))

      assert LoadTaxCreditLetterPDF.call(letter).content == saved
    end

    test "draws and saves one for a letter that has none yet", %{member: member} do
      letter = member |> tax_credit_letter_fixture() |> Repo.preload(member: :team)
      assert LetterPDF.attachment(letter) == nil

      attachment = LoadTaxCreditLetterPDF.call(letter)

      assert attachment.content =~ "%PDF"
      assert LetterPDF.attachment(letter) == attachment
    end
  end

  describe "replacing a letter" do
    setup %{team: team, member: member} do
      letter = team |> create(member) |> Map.put(:primary_minutes, -1)
      %{letter: letter, before: LetterPDF.attachment(letter).content}
    end

    test "saves its new PDF in place of the old", %{team: team, letter: letter, before: before} do
      replaced = ReplaceTaxCreditLetter.call(team, letter)

      assert LetterPDF.attachment(replaced).content != before
      assert Repo.aggregate(LetterPDF, :count) == 1
      assert Repo.aggregate(LetterPDFFile, :count) == 1
    end

    test "drops the old PDF when the new text can't be drawn", %{team: team, letter: letter} do
      letter.member |> Ecto.Changeset.change(name: @past_win_ansi) |> Repo.update!()
      letter = Repo.preload(letter, [member: :team], force: true)

      replaced = ReplaceTaxCreditLetter.call(team, letter)

      assert replaced.letter_content =~ @past_win_ansi
      assert LetterPDF.attachment(replaced) == nil
    end
  end

  test "deleting a letter deletes its PDF", %{team: team, member: member} do
    team |> create(member) |> DeleteTaxCreditLetter.call()

    assert Repo.aggregate(TaxCreditLetter, :count) == 0
    assert Repo.aggregate(LetterPDF, :count) == 0
    assert Repo.aggregate(LetterPDFFile, :count) == 0
  end
end
