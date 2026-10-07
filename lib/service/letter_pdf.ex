defmodule Service.PDFLetter do
  alias Service.Temp

  @one_inch 72
  @signature_max_width 3 * @one_inch
  @signature_max_height 0.75 * @one_inch
  # Space above and below the signature.
  @signature_gap 6
  @qr_size @one_inch

  @doc "The letter's PDF, locked against edits so it can only be printed."
  def build(options), do: options |> render() |> Service.PDFLock.lock()

  @doc "The letter's PDF before `build/1` locks it."
  def render(options) do
    temp_path = write_to_temp_path(options)
    pdf_contents = File.read!(temp_path)
    File.rm(temp_path)
    pdf_contents
  end

  def write_to_temp_path(options) do
    temp_path = Temp.path()

    {:ok, pdf} = Pdf.new(size: :letter)

    pdf
    |> Pdf.set_info(
      title: options.title,
      author: options.author,
      creator: options.creator,
      created: Date.utc_today(),
      modified: Date.utc_today()
    )
    |> add_logo(options)
    |> add_text_content(options)
    |> add_qr_code(options)
    |> Pdf.write_to(temp_path)
    |> Pdf.cleanup()

    temp_path
  end

  # The logo is PNG bytes, padded square so one inch wide is one inch tall.
  defp add_logo(pdf, %{logo: nil}), do: pdf

  defp add_logo(pdf, options) do
    image_size = @one_inch
    %{width: width, height: height} = Pdf.size(pdf)

    pdf
    |> Pdf.add_image(
      {width - @one_inch - image_size, height - @one_inch - image_size},
      {:binary, options.logo},
      width: image_size
    )
  end

  # Without a signature, the letter is one block of text, as it always was. With one,
  # the body, the signature, and the signer block are drawn in turn, so the image lands
  # where the blank lines were.
  defp add_text_content(pdf, %{signature: signature, body: body, signer: signer})
       when is_binary(signature) do
    %{width: width, height: height} = Pdf.size(pdf)
    text_width = width - 2 * @one_inch

    pdf =
      pdf
      |> set_text_font()
      |> Pdf.text_wrap!(
        {@one_inch, height - @one_inch},
        {text_width, height - 2 * @one_inch},
        body
      )

    {image_width, image_height} = signature_size(signature)
    image_bottom = Pdf.cursor(pdf) - @signature_gap - image_height

    pdf
    |> Pdf.add_image({@one_inch, image_bottom}, {:binary, signature}, width: image_width)
    |> Pdf.text_wrap!(
      {@one_inch, image_bottom - @signature_gap},
      {text_width, image_bottom - @one_inch},
      signer
    )
  end

  defp add_text_content(pdf, options) do
    %{width: width, height: height} = Pdf.size(pdf)

    pdf
    |> set_text_font()
    |> Pdf.text_wrap!(
      {@one_inch, height - @one_inch},
      {width - 2 * @one_inch, height - 2 * @one_inch},
      options.content
    )
  end

  # The letter's verify link, bottom right, its bottom edge level with the last line of
  # text. That's the signer block and reference number, short lines that leave the space.
  # Each run of dark modules in a row is one rectangle, so no seams show between them.
  defp add_qr_code(pdf, %{qr_url: url}) when is_binary(url) do
    %{width: width} = Pdf.size(pdf)
    top_left = {width - @one_inch - @qr_size, Pdf.cursor(pdf) + @qr_size}

    url
    |> qr_rectangles(top_left)
    |> Enum.reduce(Pdf.set_fill_color(pdf, :black), fn {origin, size}, pdf ->
      Pdf.rectangle(pdf, origin, size)
    end)
    |> Pdf.fill()
  end

  defp add_qr_code(pdf, _options), do: pdf

  # `{origin, size}` of each rectangle, in PDF points, which run up from the bottom.
  defp qr_rectangles(url, {left, top}) do
    rows = url |> EQRCode.encode(:m) |> Map.fetch!(:matrix) |> Tuple.to_list()
    module = @qr_size / length(rows)

    for {row, y} <- Enum.with_index(rows), {x, length} <- dark_runs(Tuple.to_list(row)) do
      {{left + x * module, top - (y + 1) * module}, {length * module, module}}
    end
  end

  # `{start, length}` of each run of 1s.
  defp dark_runs(modules) do
    modules
    |> Enum.with_index()
    |> Enum.chunk_by(fn {module, _x} -> module end)
    |> Enum.filter(fn [{module, _x} | _rest] -> module == 1 end)
    |> Enum.map(fn [{_module, x} | _rest] = run -> {x, length(run)} end)
  end

  defp set_text_font(pdf) do
    pdf
    |> Pdf.set_font("Helvetica", 12)
    |> Pdf.set_text_leading(14.4)
  end

  # Fits the signature in 3 inches by 3/4 of an inch, keeping its shape.
  defp signature_size(png) do
    {width, height} = png_size(png)
    scale = min(@signature_max_width / width, @signature_max_height / height)
    {width * scale, height * scale}
  end

  # cspell:ignore IHDR
  # The PNG header chunk: width and height follow the 8-byte signature and chunk type.
  defp png_size(
         <<_signature::binary-8, _length::32, "IHDR", width::32, height::32, _rest::binary>>
       ),
       do: {width, height}
end
