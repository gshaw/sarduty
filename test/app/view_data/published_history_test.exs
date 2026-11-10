defmodule App.ViewData.PublishedHistoryTest do
  use ExUnit.Case, async: true

  alias App.Model.PublishedPDF
  alias App.ViewData.PublishedHistory

  @names %{1 => "Alex Chen", 2 => "Sam Rivera"}

  defp pdf(id, inserted_at, attrs \\ []),
    do:
      struct!(
        PublishedPDF,
        [id: id, code: "C#{id}", user_id: 1, inserted_at: inserted_at] ++ attrs
      )

  defp rows(pdfs), do: pdfs |> PublishedHistory.rows(@names) |> Enum.map(&{&1.what, &1.pdf.id})

  test "newest first: published, emailed, published again, withdrawn" do
    first =
      pdf(1, ~U[2026-10-10 18:50:00Z],
        replaced_by_id: 2,
        email_status: :sent,
        emailed_at: ~U[2026-10-10 18:51:00Z]
      )

    second =
      pdf(2, ~U[2026-11-09 18:50:00Z], withdrawn_at: ~U[2026-11-10 09:00:00Z], withdrawn_by_id: 2)

    assert rows([second, first]) == [
             {:withdrawn, 2},
             {:published_again, 2},
             {:emailed, 1},
             {:published, 1}
           ]

    assert [%{by: "Sam Rivera"}, %{by: "Alex Chen"}, %{by: nil}, %{by: "Alex Chen"}] =
             PublishedHistory.rows([second, first], @names)
  end

  test "an email sent before its time was kept shows with no time, after its publish" do
    letter = pdf(1, ~U[2026-10-10 18:50:00Z], email_status: :sent)

    assert [%{what: :emailed, at: nil}, %{what: :published, at: ~U[2026-10-10 18:50:00Z]}] =
             PublishedHistory.rows([letter], @names)
  end

  test "a send that's waiting or failed isn't History" do
    assert rows([pdf(1, ~U[2026-10-10 18:50:00Z], email_status: :failed)]) == [{:published, 1}]
    assert rows([pdf(1, ~U[2026-10-10 18:50:00Z], email_status: :sending)]) == [{:published, 1}]
  end
end
