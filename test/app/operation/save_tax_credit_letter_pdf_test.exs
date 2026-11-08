# cspell:ignore Łukasz Nowak -- a Polish name, past WinAnsi (#917)
defmodule App.Operation.SaveTaxCreditLetterPDFTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.SavedPDF
  alias App.Model.SavedPDFFile
  alias App.Model.TaxCreditLetter
  alias App.Operation.CreateTaxCreditLetter
  alias App.Operation.DeleteTaxCreditLetter
  alias App.Operation.ReplaceTaxCreditLetter

  # Ł is past WinAnsi, all the pdf package wrote before letters printed with Typst (#917).
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
               SavedPDF.letter_attachment(letter)
    end

    test "saves one for a name past WinAnsi (#917)", %{team: team} do
      member = member_fixture(team, %{name: @past_win_ansi})
      letter = create(team, member)

      assert letter.letter_content =~ @past_win_ansi
      assert %{content: "%PDF" <> _rest} = SavedPDF.letter_attachment(letter)
    end
  end

  describe "replacing a letter" do
    setup %{team: team, member: member} do
      letter = team |> create(member) |> Map.put(:primary_minutes, -1)
      %{letter: letter, before: SavedPDF.letter_attachment(letter).content}
    end

    test "saves its new PDF in place of the old", %{team: team, letter: letter, before: before} do
      replaced = ReplaceTaxCreditLetter.call(team, letter)

      assert SavedPDF.letter_attachment(replaced).content != before
      assert Repo.aggregate(SavedPDF, :count) == 1
      assert Repo.aggregate(SavedPDFFile, :count) == 1
    end

    test "saves the new PDF for a name past WinAnsi", %{team: team, letter: letter} do
      letter.member |> Ecto.Changeset.change(name: @past_win_ansi) |> Repo.update!()
      letter = Repo.preload(letter, [member: :team], force: true)

      replaced = ReplaceTaxCreditLetter.call(team, letter)

      assert replaced.letter_content =~ @past_win_ansi
      assert %{content: "%PDF" <> _rest} = SavedPDF.letter_attachment(replaced)
    end
  end

  test "deleting a letter deletes its PDF", %{team: team, member: member} do
    team |> create(member) |> DeleteTaxCreditLetter.call()

    assert Repo.aggregate(TaxCreditLetter, :count) == 0
    assert Repo.aggregate(SavedPDF, :count) == 0
    assert Repo.aggregate(SavedPDFFile, :count) == 0
  end
end
