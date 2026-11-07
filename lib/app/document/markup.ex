defmodule App.Document.Markup do
  @moduledoc """
  Typst markup for an evaluated App.Document (#918): what `App.Document.evaluate/3`
  gives, laid out on letter paper. Pure: it returns the markup and the files it reads,
  and App.Operation.PrintDocument runs Typst.

  Every value goes in as a Typst string, never as markup, so a name with a `*` or a `#`
  prints as written. Lengths are points from the page's edges, as the places say.

  - A flow down is a block of lines, each `leading` below the last. A space is a blank
    line, and a picture is fitted in its box, keeping its shape, with `pad` above and
    below.
  - A flow across is a row of pictures each `height` tall, the last at the right.
  - An image place is a picture, or `{:qr, link}`, a QR code as an SVG from EQRCode.
    `level with` puts its bottom edge level with a flow's last line.
  """

  @page_width 612
  @page_height 792

  @doc """
  `{markup, files}`: the Typst source, and each file it reads by name. `sample_mark` is
  a picture drawn over the whole page, for a Try a demo team (#857).
  """
  def typst(output, opts \\ []) do
    {places, files} =
      output.places
      |> Enum.map_reduce(%{}, fn place, files -> place(place, files) end)

    {mark, files} = sample_mark(Keyword.get(opts, :sample_mark), files)

    markup =
      [
        document(output),
        ~s|#set page(width: #{pt(@page_width)}, height: #{pt(@page_height)}, margin: 0pt)\n|,
        ~s|#set text(font: "Arimo", fallback: false)\n|,
        places,
        mark
      ]
      |> IO.iodata_to_binary()

    {markup, files}
  end

  defp document(%{title: title, author: author}) do
    fields =
      [title: title, author: author]
      |> Enum.reject(fn {_name, value} -> value in [nil, ""] end)
      |> Enum.map_join(", ", fn {name, value} -> "#{name}: #{string(value)}" end)

    if fields == "", do: "", else: "#set document(#{fields})\n"
  end

  defp sample_mark(nil, files), do: {"", files}

  defp sample_mark(png, files) do
    {~s|#place(top + left, image("sample-mark.png", width: #{pt(@page_width)}))\n|,
     Map.put(files, "sample-mark.png", png)}
  end

  # Places

  defp place(%{kind: :flow, across: false} = place, files) do
    width = @page_width - place.left - Map.get(place, :right, 0)

    {items, files} =
      place.value |> Enum.with_index() |> Enum.map_reduce(files, &line(&1, place, &2))

    markup = [
      "#let #{var(place)} = block(width: #{pt(width)}, {\n",
      "  set text(size: #{pt(size(place))}, top-edge: #{pt(ascent(place))}, bottom-edge: \"baseline\")\n",
      "  set par(leading: #{pt(gap(place))}, spacing: #{pt(gap(place))})\n",
      items,
      "})\n",
      "#let #{var(place)}_top = #{pt(place.top)}\n",
      "#place(top + left, dx: #{pt(place.left)}, dy: #{pt(place.top)}, #{var(place)})\n"
    ]

    {markup, files}
  end

  defp place(%{kind: :flow, across: true} = place, files) do
    {images, files} =
      place.value
      |> Enum.with_index()
      |> Enum.map_reduce(files, fn {{:image, bytes, _options}, i}, files ->
        name = file_name(place, i, bytes)
        {~s|image("#{name}", height: #{pt(place.height)})|, Map.put(files, name, bytes)}
      end)

    markup =
      if images == [],
        do: "",
        else: [
          "#place(top + right, dx: -#{pt(Map.get(place, :right, 0))}, dy: #{pt(place.top)}, ",
          "stack(dir: ltr, spacing: #{pt(Map.get(place, :gap, 0))}, #{Enum.join(images, ", ")}))\n"
        ]

    {markup, files}
  end

  defp place(%{kind: :image, value: nil}, files), do: {"", files}

  defp place(%{kind: :image, value: value} = place, files) do
    bytes = image_bytes(value)
    name = file_name(place, 0, bytes)
    image = ~s|image("#{name}", width: #{pt(place.width)}, height: #{pt(place.height)})|
    left = Map.get(place, :left) || @page_width - Map.get(place, :right, 0) - place.width

    markup =
      case place do
        %{level_with: flow} when is_binary(flow) ->
          flow_top = "#{var(flow)}_top"

          [
            "#context place(top + left, dx: #{pt(left)}, ",
            "dy: #{flow_top} + measure(#{var(flow)}).height - #{pt(place.height)}, #{image})\n"
          ]

        _place ->
          "#place(top + left, dx: #{pt(left)}, dy: #{pt(Map.get(place, :top, 0))}, #{image})\n"
      end

    {markup, Map.put(files, name, bytes)}
  end

  defp place(%{kind: :text, value: text} = place, files) do
    width = @page_width - place.left - Map.get(place, :right, 0)

    markup =
      if text in [nil, ""],
        do: "",
        else:
          "#place(top + left, dx: #{pt(place.left)}, dy: #{pt(place.top)}, " <>
            "block(width: #{pt(width)}, text(size: #{pt(size(place))}, #{string(text)})))\n"

    {markup, files}
  end

  # A flow down's items. A blank line is hidden text, so it's exactly a line's height.
  defp line({{:text, text}, _i}, _place, files) do
    lines = text |> String.split(~r/\r?\n/) |> Enum.map(&"  par(#{string(&1)})\n")
    {lines, files}
  end

  defp line({{:space, count}, _i}, _place, files),
    do: {List.duplicate("  par(hide[x])\n", count), files}

  defp line({{:image, bytes, options}, i}, place, files) do
    name = file_name(place, i, bytes)
    {width, height} = fit(bytes, options)
    pad = Map.get(options, :pad, 0)

    markup =
      "  block(above: #{pt(pad + gap(place))}, below: #{pt(pad)}, " <>
        "image(\"#{name}\", width: #{pt(width)}, height: #{pt(height)}))\n"

    {markup, Map.put(files, name, bytes)}
  end

  # The flow's own name, and where it starts, for a place level with it.
  defp var(%{name: name}), do: var(name)
  defp var(name) when is_binary(name), do: "place_#{name}"

  defp size(place), do: Map.get(place, :size, 12)

  # How far the first line's baseline sits below the flow's top, as the letters drawn
  # before Typst had it, and the space from one line's baseline to the next line's top.
  defp ascent(place), do: size(place) * 0.75
  defp gap(place), do: Map.get(place, :leading, size(place) * 1.2) - ascent(place)

  # Pictures

  defp image_bytes({:qr, link}), do: link |> EQRCode.encode(:m) |> EQRCode.svg()
  defp image_bytes(bytes) when is_binary(bytes), do: bytes

  defp file_name(place, i, bytes), do: "#{place.name}-#{i}.#{extension(bytes)}"

  defp extension(<<0x89, "PNG", _rest::binary>>), do: "png"
  defp extension(<<0xFF, 0xD8, _rest::binary>>), do: "jpg"
  defp extension(_bytes), do: "svg"

  # Fits the picture in the item's box, keeping its shape.
  defp fit(bytes, %{width: max_width, height: max_height}) do
    case size_of(bytes) do
      {width, height} when width > 0 and height > 0 ->
        scale = min(max_width / width, max_height / height)
        {width * scale, height * scale}

      _unknown ->
        {max_width, max_height}
    end
  end

  # A PNG's width and height follow its 8-byte signature and the header chunk's type.
  defp size_of(<<_signature::binary-8, _length::32, "IHDR", width::32, height::32, _::binary>>),
    do: {width, height}

  defp size_of(_bytes), do: nil

  # Typst values

  defp pt(points) when is_integer(points), do: "#{points}pt"
  defp pt(points) when is_float(points), do: "#{Float.round(points, 3)}pt"

  @doc "`text` as a Typst string, so it prints as written."
  def string(text) do
    escaped =
      text
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    ~s|"#{escaped}"|
  end
end
