defmodule App.ViewData.PublishedHistoryTest do
  use ExUnit.Case, async: true

  alias App.Model.PublishedPDF
  alias App.ViewData.PublishedHistory

  @names %{1 => "Alex Chen", 2 => "Sam Rivera"}

  defp pdf(id, inserted_at, attrs),
    do:
      struct!(
        PublishedPDF,
        [id: id, code: "C#{id}", user_id: 1, inserted_at: inserted_at] ++ attrs
      )

  defp rows(pdfs), do: pdfs |> PublishedHistory.rows(@names) |> Enum.map(&{&1.what, &1.pdf.id})

  test "newest first: published and withdrawn; one that replaced another is Published too" do
    first = pdf(1, ~U[2026-10-10 18:50:00Z], replaced_by_id: 2)

    second =
      pdf(2, ~U[2026-11-09 18:50:00Z], withdrawn_at: ~U[2026-11-10 09:00:00Z], withdrawn_by_id: 2)

    assert rows([second, first]) == [
             {:withdrawn, 2},
             {:published, 2},
             {:published, 1}
           ]

    assert [%{by: "Sam Rivera"}, %{by: "Alex Chen"}, %{by: "Alex Chen"}] =
             PublishedHistory.rows([second, first], @names)
  end

  # A PDF keeps only its last email, so re-sends would go missing (#995).
  test "emails aren't History, sent, waiting, or failed" do
    for status <- [:sent, :sending, :failed] do
      letter =
        pdf(1, ~U[2026-10-10 18:50:00Z],
          email_status: status,
          emailed_at: ~U[2026-10-10 18:51:00Z]
        )

      assert rows([letter]) == [{:published, 1}]
    end
  end
end
