# cspell:ignore Łukasz Nowak -- a Polish name, past WinAnsi (#917)
defmodule App.Operation.SaveTaxCreditLetterPDFTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.PublishedPDF
  alias App.Model.PublishedPDFFile
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
               PublishedPDF.letter_attachment(letter)
    end

    test "saves one for a name past WinAnsi (#917)", %{team: team} do
      member = member_fixture(team, %{name: @past_win_ansi})
      letter = create(team, member)

      assert letter.letter_content =~ @past_win_ansi
      assert %{content: "%PDF" <> _rest} = PublishedPDF.letter_attachment(letter)
    end
  end

  describe "replacing a letter" do
    setup %{team: team, member: member} do
      letter = team |> create(member) |> Map.put(:primary_minutes, -1)
      %{letter: letter, before: PublishedPDF.letter_attachment(letter).content}
    end

    test "publishes its new PDF with a new ID, and the old one says Replaced (#970)",
         %{team: team, letter: letter, before: before} do
      old = letter.pdf
      replaced = ReplaceTaxCreditLetter.call(team, letter)

      assert PublishedPDF.letter_attachment(replaced).content != before
      assert replaced.pdf.code != old.code
      assert old |> Repo.reload!() |> PublishedPDF.status() == :replaced
      assert Repo.aggregate(PublishedPDFFile, :count) == 2
    end

    test "saves the new PDF for a name past WinAnsi", %{team: team, letter: letter} do
      letter.member |> Ecto.Changeset.change(name: @past_win_ansi) |> Repo.update!()
      letter = Repo.preload(letter, [member: :team], force: true)

      replaced = ReplaceTaxCreditLetter.call(team, letter)

      assert replaced.letter_content =~ @past_win_ansi
      assert %{content: "%PDF" <> _rest} = PublishedPDF.letter_attachment(replaced)
    end
  end

  test "deleting a letter deletes its PDF", %{team: team, member: member} do
    team |> create(member) |> DeleteTaxCreditLetter.call()

    assert Repo.aggregate(TaxCreditLetter, :count) == 0
    assert Repo.aggregate(PublishedPDF, :count) == 0
    assert Repo.aggregate(PublishedPDFFile, :count) == 0
  end
end
