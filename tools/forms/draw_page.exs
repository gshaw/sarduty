# Draws a form's blank page from its Typst program, beside it (#950): `supplement.typ`
# makes `supplement.pdf`. It runs Typst as SAR Duty does (Service.Typst), with only
# priv/fonts, so App.FormsTest can check the PDF is the program's.
#
#   mise exec -- mix run --no-start tools/forms/draw_page.exs priv/forms/bcsara/supplement.typ

case System.argv() do
  [source] ->
    pdf = Path.rootname(source) <> ".pdf"

    case source |> File.read!() |> Service.Typst.compile() do
      {:ok, bytes} ->
        File.write!(pdf, bytes)
        IO.puts("Drew #{pdf}")

      {:error, reason} ->
        Mix.raise("Typst could not draw #{source}: #{reason}")
    end

  _other ->
    Mix.raise("Give the form's Typst program, such as priv/forms/bcsara/supplement.typ.")
end
