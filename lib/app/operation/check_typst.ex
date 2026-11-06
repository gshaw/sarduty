defmodule App.Operation.CheckTypst do
  @moduledoc """
  Step 0 of #918: proves Typst can make a tax credit letter on this server before any
  letter depends on it. It makes a test letter with everything a real one has (names
  past WinAnsi, bold and italic, a logo made by libvips, a transparent PNG, the QR code
  as an SVG from EQRCode), checks the PDF, and locks it print-only with `PDFLock`.
  Adminland › Integrations runs it, and the locked PDF downloads so a person can look.
  """

  alias Service.PDFLock
  alias Service.Typst

  # cspell:ignore Łukasz Nowak Tomáš Dvořák Nguyễn Văn Renée Côté -- names past WinAnsi, the reason for #917
  @names ["Łukasz Nowak", "Tomáš Dvořák", "Nguyễn Văn An", "Renée Côté"]
  @fonts MapSet.new(~w(Arimo-Regular Arimo-Bold Arimo-Italic Arimo-BoldItalic))

  @doc "`{:ok, message, locked_pdf}` or `{:error, message}`."
  def call do
    started = System.monotonic_time(:millisecond)

    with {:ok, version} <- check_version(),
         {:ok, files} <- files(),
         {:ok, pdf} <- Typst.compile(source(), files),
         :ok <- check_pdf(pdf),
         {:ok, locked} <- lock(pdf) do
      ms = System.monotonic_time(:millisecond) - started

      {:ok, "Typst #{version} works. It made a test letter in #{ms} ms and locked it print-only.",
       locked}
    else
      {:error, reason} -> {:error, "Typst doesn't work here. #{reason}"}
    end
  end

  defp check_version do
    case Typst.installed_version() do
      {:ok, version} ->
        if version == Typst.version(),
          do: {:ok, version},
          else: {:error, "It's version #{version}; SAR Duty pins #{Typst.version()}."}

      {:error, reason} ->
        {:error, "#{reason}."}
    end
  end

  # The logo goes through libvips as a team's logo does; the sample mark is a PNG with
  # transparency; the QR code is vector.
  defp files do
    logo = app_file("priv/static/images/sarduty-logo-96.png")

    case logo |> File.read!() |> Service.Image.pad_square(300) do
      {:ok, logo} ->
        qr = "https://sarduty.com/verify/TEST" |> EQRCode.encode() |> EQRCode.svg()
        mark = "priv/pdf/sample-mark.png" |> app_file() |> File.read!()

        {:ok, %{"logo.png" => logo, "mark.png" => mark, "qr.svg" => qr}}

      {:error, reason} ->
        {:error, "libvips couldn't make the logo: #{inspect(reason)}."}
    end
  end

  @doc false
  def source do
    """
    #set document(title: "Typst test letter", author: "SAR Duty")
    #set page(paper: "us-letter", margin: 1in)
    #set text(font: "Arimo", size: 12pt, fallback: false)
    #set par(leading: 0.4em)

    #place(top + right, dy: -0.5in, image("logo.png", width: 1in))

    Typst test letter, made in Adminland › Integrations.

    #{Enum.join(@names, "\\\n")}

    *Bold*, _italic_, and *_bold italic_*.

    #place(bottom + right, image("qr.svg", width: 1in))
    #place(top + left, dx: -1in, dy: -1in, image("mark.png", width: 8.5in))
    """
  end

  @doc false
  # What a reader can see without unpacking streams: the fonts embedded and the images.
  def check_pdf(pdf) do
    fonts =
      ~r"/BaseFont\s*/[A-Z]{6}\+([\w-]+)"
      |> Regex.scan(pdf, capture: :all_but_first)
      |> MapSet.new(&hd/1)

    images = length(Regex.scan(~r"/Subtype\s*/Image", pdf))

    cond do
      fonts != @fonts ->
        {:error, "The PDF has the fonts #{Enum.join(fonts, ", ")}, not all four of Arimo's."}

      images < 2 ->
        {:error, "The PDF has #{images} images, not the logo and the sample mark."}

      true ->
        :ok
    end
  end

  defp lock(pdf) do
    locked = PDFLock.lock(pdf)

    case PDFLock.file_key(locked) do
      {:ok, _key} -> {:ok, locked}
      :error -> {:error, "PDFLock locked it, but it doesn't open."}
    end
  rescue
    error in ArgumentError -> {:error, "PDFLock couldn't read it: #{Exception.message(error)}."}
  end

  # A release keeps priv/ under lib/sarduty-<version>/, not where the source was built.
  defp app_file(path), do: Application.app_dir(:sarduty, path)
end
