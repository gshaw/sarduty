defmodule App.Operation.RenewLetterCodesTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.PublishedPDF
  alias App.Operation.RenewLetterCodes
  alias App.Worker.RenewLetterCodesWorker

  # Letters from before #970 carry codes that no longer verify (#970).
  setup do
    team = team_fixture()
    member = member_fixture(team)

    old =
      for {code, year} <- [{"SRVTC-K7Q4M2XA", 2025}, {"SRVTC-M4K11", 2020}],
          do:
            tax_credit_letter_fixture(member, %{
              code: code,
              year: year,
              primary_minutes: 90,
              secondary_minutes: 0
            })

    new = tax_credit_letter_fixture(member, %{code: "K7Q4M2XA9HVB3TN", year: 2024})
    %{old: old, new: new}
  end

  test "gives each old letter an ID and prints its PDF again, in place", %{old: old, new: new} do
    assert RenewLetterCodes.remaining() == 2
    before = Map.new(old, &{&1.pdf.id, PublishedPDF.attachment(&1.pdf).content})

    assert RenewLetterCodes.batch(0, 10) ==
             old |> List.last() |> Map.fetch!(:pdf) |> Map.fetch!(:id)

    assert RenewLetterCodes.remaining() == 0

    for letter <- old do
      pdf = Repo.reload!(letter.pdf)
      assert PublishedPDF.parse_code(pdf.code) == pdf.code
      assert PublishedPDF.status(pdf) == :current
      assert pdf.inserted_at == letter.pdf.inserted_at

      content = PublishedPDF.attachment(pdf).content
      assert "%PDF" <> _ = content
      assert content != before[pdf.id]
      assert pdf.sha256 == :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)
      assert %{"label" => "Total hours", "text" => "1h 30m"} in pdf.shows
    end

    # One row each, nothing Replaced, and a letter with an ID already is left alone.
    assert Repo.aggregate(PublishedPDF, :count) == 3
    assert Repo.reload!(new.pdf).code == "K7Q4M2XA9HVB3TN"
    assert RenewLetterCodes.batch(0, 10) == nil
  end

  test "the worker goes a batch at a time until none are left" do
    # Jobs run inline in tests, the next batch's too.
    RenewLetterCodesWorker.enqueue()
    assert RenewLetterCodes.remaining() == 0
  end
end
