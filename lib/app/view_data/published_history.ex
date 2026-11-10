defmodule App.ViewData.PublishedHistory do
  @moduledoc """
  A subject's published PDFs as History rows, newest first (#970): a letter's for its
  member and year, a form's for its activity. Built from what each PDF keeps, so nothing
  writes History: published, published again, and withdrawn. Emails aren't History: a
  PDF keeps only its last email, so re-sends would go missing, and the Published section
  says where it went (#995). A member's downloads aren't kept either. Pure: the PDFs,
  with `user` and `withdrawn_by` loaded, and their names in.
  """

  alias App.Model.PublishedPDF

  @doc """
  `[%{at, what, pdf, by}]`: `what` is `:published`, `:published_again`, or `:withdrawn`,
  and `by` a name or nil. `names` maps a user's id to the name shown for them.
  """
  def rows(pdfs, names) do
    replacing = MapSet.new(pdfs, & &1.replaced_by_id)

    pdfs
    |> Enum.flat_map(&pdf_rows(&1, MapSet.member?(replacing, &1.id), names))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&{&1.at, &1.order}, &newer?/2)
    |> Enum.map(&Map.delete(&1, :order))
  end

  defp pdf_rows(pdf, replaced_another?, names) do
    published = if replaced_another?, do: :published_again, else: :published

    [
      row(pdf.inserted_at, published, pdf, name(names, pdf.user_id), 0),
      withdrawn(pdf, names)
    ]
  end

  # Newest first; at the same moment, a withdraw before a publish.
  defp newer?({a, x}, {b, y}) do
    case DateTime.compare(a, b) do
      :eq -> x >= y
      order -> order == :gt
    end
  end

  defp name(_names, nil), do: nil
  defp name(names, user_id), do: Map.get(names, user_id)

  defp withdrawn(%PublishedPDF{withdrawn_at: %DateTime{} = at} = pdf, names),
    do: row(at, :withdrawn, pdf, name(names, pdf.withdrawn_by_id), 1)

  defp withdrawn(_pdf, _names), do: nil

  defp row(at, what, pdf, by, order), do: %{at: at, what: what, pdf: pdf, by: by, order: order}

  @doc "Who published and withdrew `pdfs`, by user id, through `name_fn` (a user to a name)."
  def names(pdfs, name_fn) do
    pdfs
    |> Enum.flat_map(&[&1.user, &1.withdrawn_by])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Map.new(&{&1.id, name_fn.(&1)})
  end
end
