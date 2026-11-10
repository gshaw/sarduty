defmodule App.ViewData.PublishedHistory do
  @moduledoc """
  A subject's published PDFs as History rows, newest first (#970): a letter's for its
  member and year, a form's for its activity. Built from what each PDF keeps, so nothing
  writes History: published, published again, emailed (a letter's last email), and
  withdrawn. A member's downloads aren't kept. Pure: the PDFs, with `user` and
  `withdrawn_by` loaded, and their names in.
  """

  alias App.Model.PublishedPDF

  @doc """
  `[%{at, what, pdf, by}]`: `what` is `:published`, `:published_again`, `:emailed`, or
  `:withdrawn`, `by` a name or nil, and `at` nil for an email sent before its time was
  kept. `names` maps a user's id to the name shown for them.
  """
  def rows(pdfs, names) do
    replacing = MapSet.new(pdfs, & &1.replaced_by_id)
    name = fn user_id -> user_id && Map.get(names, user_id) end

    pdfs
    |> Enum.flat_map(fn pdf ->
      published = if MapSet.member?(replacing, pdf.id), do: :published_again, else: :published

      [
        row(pdf.inserted_at, pdf.inserted_at, published, pdf, name.(pdf.user_id), 0),
        emailed(pdf),
        pdf.withdrawn_at &&
          row(pdf.withdrawn_at, pdf.withdrawn_at, :withdrawn, pdf, name.(pdf.withdrawn_by_id), 2)
      ]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&{&1.sort, &1.order}, fn {a, x}, {b, y} ->
      case DateTime.compare(a, b) do
        :eq -> x >= y
        order -> order == :gt
      end
    end)
    |> Enum.map(&Map.drop(&1, [:sort, :order]))
  end

  # An email sent before its time was kept went with its letter, so it sorts there.
  defp emailed(%PublishedPDF{emailed_at: %DateTime{} = at} = pdf),
    do: row(at, at, :emailed, pdf, nil, 1)

  defp emailed(%PublishedPDF{email_status: :sent} = pdf),
    do: row(nil, pdf.inserted_at, :emailed, pdf, nil, 1)

  defp emailed(_pdf), do: nil

  defp row(at, sort, what, pdf, by, order),
    do: %{at: at, sort: sort, what: what, pdf: pdf, by: by, order: order}

  @doc "Who published and withdrew `pdfs`, by user id, through `name_fn` (a user to a name)."
  def names(pdfs, name_fn) do
    pdfs
    |> Enum.flat_map(&[&1.user, &1.withdrawn_by])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Map.new(&{&1.id, name_fn.(&1)})
  end
end
