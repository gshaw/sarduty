# cspell:ignore Łukasz Nowak -- a Polish name, past WinAnsi (#917)
defmodule App.Worker.SaveLetterPDFsWorkerTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Event
  alias App.Model.LetterPDF
  alias App.Model.TaxCreditLetter
  alias App.Worker.SaveLetterPDFsWorker

  setup do
    team = team_fixture()
    %{team: team}
  end

  # Letters made before #918, with no PDF. Oban runs inline in tests, so each batch's
  # next one runs as it's queued.
  defp old_letters(team, count, attrs \\ %{}) do
    for _n <- 1..count, do: team |> member_fixture(attrs) |> tax_credit_letter_fixture()
  end

  test "saves a PDF for every letter, a batch at a time", %{team: team} do
    letters = old_letters(team, 30)

    assert :ok = SaveLetterPDFsWorker.perform(%Oban.Job{args: %{}})

    for letter <- letters, do: assert(LetterPDF.attachment(letter).content =~ "%PDF")

    assert %{data: %{"saved" => 30, "failed_letter_ids" => []}} =
             Event.get_last(:letter_pdfs_saved)
  end

  test "passes over a letter it can't draw, and names it (#917)", %{team: team} do
    [good] = old_letters(team, 1)

    bad =
      team
      |> member_fixture()
      |> tax_credit_letter_fixture(%{letter_content: "Name: Łukasz Nowak"})

    assert :ok = SaveLetterPDFsWorker.perform(%Oban.Job{args: %{}})

    assert LetterPDF.attachment(good)
    assert LetterPDF.attachment(bad) == nil
    failed = [bad.id]

    assert %{data: %{"saved" => 1, "failed_letter_ids" => ^failed}} =
             Event.get_last(:letter_pdfs_saved)
  end

  test "leaves a letter's saved PDF alone", %{team: team} do
    [letter] = old_letters(team, 1)
    letter = Repo.preload(letter, member: :team)
    LetterPDF.put!(letter, %{content: "kept", title: "t", filename: "t.pdf"})

    assert :ok = SaveLetterPDFsWorker.perform(%Oban.Job{args: %{}})

    assert LetterPDF.attachment(letter).content == "kept"
    assert Event.get_last(:letter_pdfs_saved) == nil
    assert Repo.aggregate(TaxCreditLetter, :count) == 1
  end
end
