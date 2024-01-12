defmodule Service.PDFLetter do
  alias Service.Temp

  @one_inch 72

  def build(options) do
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
    |> Pdf.write_to(temp_path)
    |> Pdf.cleanup()

    temp_path
  end

  defp add_logo(pdf, %{logo_path: nil}), do: pdf

  defp add_logo(pdf, options) do
    image_size = @one_inch
    %{width: width, height: height} = Pdf.size(pdf)

    pdf
    |> Pdf.add_image(
      {width - @one_inch - image_size, height - @one_inch - image_size},
      options.logo_path,
      width: image_size
    )
  end

  defp add_text_content(pdf, options) do
    %{width: width, height: height} = Pdf.size(pdf)

    pdf
    |> Pdf.set_font("Helvetica", 12)
    |> Pdf.set_text_leading(14.4)
    |> Pdf.text_wrap!(
      {@one_inch, height - @one_inch},
      {width - 2 * @one_inch, height - 2 * @one_inch},
      options.content
    )
  end
end
