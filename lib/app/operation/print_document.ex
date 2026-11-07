defmodule App.Operation.PrintDocument do
  @moduledoc """
  Prints an evaluated App.Document with Typst (#918): App.Document.Markup lays it out,
  Service.Typst makes the PDF, and a document that says `lock print` goes through
  Service.PDFLock, so it can only be printed. A form that says `page` prints on its own
  page PDF (#950), every page of it.
  """

  alias App.Document.Markup
  alias Service.Format
  alias Service.PDFLock
  alias Service.PDFPages
  alias Service.Typst

  @doc """
  `{:ok, pdf}` or `{:error, reason}` for what `App.Document.evaluate/3` gave. With
  `sample: true` the page says SAMPLE across it, for a Try a demo team (#857). `page` is
  a form's page PDF, for one that prints on it.
  """
  def call(output, opts \\ []) do
    mark = if Keyword.get(opts, :sample, false), do: sample_mark()

    with {:ok, page} <- page(output, Keyword.get(opts, :page)) do
      {markup, files} = Markup.typst(output, sample_mark: mark, page: page)
      with {:ok, pdf} <- Typst.compile(markup, files), do: {:ok, lock(pdf, output.lock)}
    end
  end

  # The form's page and how many pages it has, each place on one of them.
  defp page(%{page: true}, nil), do: {:error, "This form has no page to print on."}

  defp page(%{page: true} = output, pdf) do
    with {:ok, pages} <- check_page(output.places, pdf), do: {:ok, {pdf, pages}}
  end

  defp page(_output, _pdf), do: {:ok, nil}

  @doc """
  `{:ok, pages}`, how many pages a form's page PDF has, when every place is on one of
  them, or `{:error, reason}`. Saving a form checks its page with this
  (App.Operation.SaveForm), and printing checks it again.
  """
  def check_page(places, pdf) when is_binary(pdf) do
    with {:ok, pages} <- pages(pdf),
         :ok <- on_a_page(places, pages),
         do: {:ok, pages}
  end

  defp pages(pdf) do
    case PDFPages.count(pdf) do
      {:ok, pages} when pages > 0 -> {:ok, pages}
      _other -> {:error, "SAR Duty cannot read this form's page. Upload it as a PDF."}
    end
  end

  defp on_a_page(places, pages) do
    case Enum.find(places, &(&1.page > pages)) do
      nil ->
        :ok

      place ->
        has = Format.count(pages, one: "1 page", many: "%d pages")
        {:error, "Place #{place.name} is on page #{place.page}. The form's page has #{has}."}
    end
  end

  defp lock(pdf, :print), do: PDFLock.lock(pdf)
  defp lock(pdf, nil), do: pdf

  # SAMPLE from top left to bottom right, in translucent red, so the text under it reads
  # but no part of a printed copy can pass as real. Made by tools/sample-mark.py. A
  # release keeps priv/ under lib/sarduty-<version>/ (#931).
  defp sample_mark,
    do: :sarduty |> Application.app_dir("priv/pdf/sample-mark.png") |> File.read!()
end
