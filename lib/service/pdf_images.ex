defmodule Service.PDFImages do
  @moduledoc """
  A PDF's pages as PNGs, for a preview of what publishes (#970): Typst draws each page
  of the PDF as an image, so what shows is the PDF itself, not a second print of it.
  A locked PDF can't be read this way; only an unlocked one is previewed.
  """

  alias Service.PDFPages
  alias Service.Typst

  # Sharp on a phone or a Mac's screen at the page's width, and small enough to send.
  @ppi 110

  @doc """
  `{:ok, png}` of page 1 only, or `{:error, reason}`: the preview on a published PDF's
  page, drawn when the page asks, so nothing more is saved.
  """
  def first_page(pdf, ppi \\ @ppi) when is_binary(pdf),
    do: 1 |> source() |> Typst.compile(%{"doc.pdf" => pdf}, png: ppi)

  @doc "`{:ok, [png]}`, one for each page in order, or `{:error, reason}`."
  def pages(pdf, ppi \\ @ppi) when is_binary(pdf) do
    case PDFPages.count(pdf) do
      {:ok, count} when count > 0 -> render(pdf, 1, count, ppi, [])
      _other -> {:error, "SAR Duty cannot read this PDF's pages."}
    end
  end

  # Each page in turn, page `n` of `count`; a page that doesn't draw stops it.
  defp render(_pdf, n, count, _ppi, pngs) when n > count, do: {:ok, Enum.reverse(pngs)}

  defp render(pdf, n, count, ppi, pngs) do
    case n |> source() |> Typst.compile(%{"doc.pdf" => pdf}, png: ppi) do
      {:ok, png} -> render(pdf, n + 1, count, ppi, [png | pngs])
      {:error, reason} -> {:error, reason}
    end
  end

  defp source(n),
    do: """
    #set page(width: auto, height: auto, margin: 0pt)
    #image("doc.pdf", page: #{n})
    """
end
