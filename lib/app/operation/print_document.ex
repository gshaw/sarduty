defmodule App.Operation.PrintDocument do
  @moduledoc """
  Prints an evaluated App.Document with Typst (#918): App.Document.Markup lays it out,
  Service.Typst makes the PDF, and a document that says `lock print` goes through
  Service.PDFLock, so it can only be printed.
  """

  alias App.Document.Markup
  alias Service.PDFLock
  alias Service.Typst

  @doc """
  `{:ok, pdf}` or `{:error, reason}` for what `App.Document.evaluate/3` gave. With
  `sample: true` the page says SAMPLE across it, for a Try a demo team (#857).
  """
  def call(output, opts \\ []) do
    mark = if Keyword.get(opts, :sample, false), do: sample_mark()
    {markup, files} = Markup.typst(output, sample_mark: mark)

    with {:ok, pdf} <- Typst.compile(markup, files), do: {:ok, lock(pdf, output.lock)}
  end

  defp lock(pdf, :print), do: PDFLock.lock(pdf)
  defp lock(pdf, nil), do: pdf

  # SAMPLE from top left to bottom right, in translucent red, so the text under it reads
  # but no part of a printed copy can pass as real. Made by tools/sample-mark.py. A
  # release keeps priv/ under lib/sarduty-<version>/ (#931).
  defp sample_mark,
    do: :sarduty |> Application.app_dir("priv/pdf/sample-mark.png") |> File.read!()
end
