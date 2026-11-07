defmodule App.Document.Markup do
  @moduledoc """
  Typst markup for an evaluated App.Document (#918): what `App.Document.evaluate/3`
  gives, laid out on letter paper, or on each page of a form's own PDF (#950). Pure: it
  returns the markup and the files it reads, and App.Operation.PrintDocument runs Typst.

  Values reach Typst as data, never as Typst code: they go in `values.json`, and the
  markup reads them by key, so a name with a `*`, a `#`, or a `"` prints as written.
  Lengths are points from the page's edges, as the places say.

  - A text place wraps at its width, with lines `pitch` apart when it says so, to sit
    on a form's printed lines, its first line `indent` further in. With `lines` it
    shrinks until it fits that many. With `fit` it's one line, shrunk until it fits. Its first
    baseline is three quarters of its size below its top, as a flow's is, and its text
    starts at its left edge, wherever the place is anchored.
  - A tick is an X across its box, when its condition holds.
  - A flow down is a block of lines, each `leading` below the last. A space is a blank
    line, and a picture is fitted in its box, keeping its shape, with `pad` above and
    below.
  - A flow across is a row of pictures each `height` tall, from its right edge.
  - An image place is a picture, or `{:qr, link}`, a QR code as an SVG from EQRCode.
    `level with` puts its bottom edge level with a flow's last line.

  A form's page is `page.pdf`. Each of its pages prints at its own size, with the
  places that say that page drawn over it.
  """

  @letter_width 612
  @letter_height 792
  # The smallest size a text on its `lines` shrinks to.
  @smallest 6

  @doc """
  `{markup, files}`: the Typst source, and each file it reads by name. `sample_mark` is
  a picture drawn over each page, for a Try a demo team (#857). `page` is `{pdf, pages}`,
  a form's page and how many pages it has; without it the page is letter paper.
  """
  def typst(output, opts \\ []) do
    files = sample_mark_file(%{}, Keyword.get(opts, :sample_mark))
    page = Keyword.get(opts, :page)
    files = if page, do: Map.put(files, "page.pdf", elem(page, 0)), else: files
    values = %{"title" => output.title, "author" => output.author}

    {pages, {files, values}} =
      page
      |> page_numbers()
      |> Enum.map_reduce({files, values}, fn n, acc ->
        places = Enum.filter(output.places, &(Map.get(&1, :page, 1) == n))
        {body, acc} = Enum.map_reduce(places, acc, &place/2)
        {page_markup(n, page, [body, mark(files)]), acc}
      end)

    markup =
      IO.iodata_to_binary([
        ~s|#let v = json("values.json")\n|,
        document(values),
        ~s|#set text(font: "Arimo", fallback: false)\n|,
        pages
      ])

    {markup, Map.put(files, "values.json", Jason.encode!(values))}
  end

  defp page_numbers(nil), do: [1]
  defp page_numbers({_pdf, pages}), do: Enum.to_list(1..pages)

  defp document(values) do
    case Enum.filter(["title", "author"], &(values[&1] not in [nil, ""])) do
      [] -> ""
      names -> "#set document(#{Enum.map_join(names, ", ", &"#{&1}: v.at(\"#{&1}\")")})\n"
    end
  end

  # Letter paper, or one of the form's pages at its own size, drawn under the values.
  # `page-width` is the page's width, for a place that reaches its right edge.
  defp page_markup(_n, nil, body) do
    [
      "#set page(width: #{pt(@letter_width)}, height: #{pt(@letter_height)}, margin: 0pt)\n",
      "#let page-width = #{pt(@letter_width)}\n",
      body
    ]
  end

  defp page_markup(n, _page, body) do
    [
      "\#{\n",
      ~s|  let page-image = image("page.pdf", page: #{n})\n|,
      "  context {\n",
      "    let size = measure(page-image)\n",
      "    page(width: size.width, height: size.height, margin: 0pt, background: page-image)[\n",
      "#let page-width = size.width\n",
      body,
      "    ]\n",
      "  }\n",
      "}\n"
    ]
  end

  defp sample_mark_file(files, nil), do: files
  defp sample_mark_file(files, png), do: Map.put(files, "sample-mark.png", png)

  defp mark(%{"sample-mark.png" => _}),
    do: ~s|#place(top + left, image("sample-mark.png", width: page-width))\n|

  defp mark(_files), do: ""

  # Places, each `{markup, {files, values}}`

  defp place(%{kind: :flow, across: false} = place, {files, values}) do
    {items, {files, values}} =
      place.value
      |> Enum.with_index()
      |> Enum.map_reduce({files, Map.put(values, place.name, [])}, &line(&1, place, &2))

    markup = [
      "#let #{var(place)} = block(width: #{width(place)}, {\n",
      "  set align(left)\n",
      "  set text(size: #{pt(size(place))}, top-edge: #{pt(ascent(place))}, bottom-edge: \"baseline\")\n",
      "  set par(leading: #{pt(gap(place))}, spacing: #{pt(gap(place))})\n",
      items,
      "})\n",
      "#let #{var(place)}_top = #{pt(place.top)}\n",
      "#place(#{at(place)}, #{var(place)})\n"
    ]

    {markup, {files, values}}
  end

  defp place(%{kind: :flow, across: true} = place, {files, values}) do
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
          "#place(#{at(place)}, ",
          "stack(dir: ltr, spacing: #{pt(Map.get(place, :gap, 0))}, #{Enum.join(images, ", ")}))\n"
        ]

    {markup, {files, values}}
  end

  defp place(%{kind: :image, value: nil}, acc), do: {"", acc}

  defp place(%{kind: :image, value: value} = place, {files, values}) do
    bytes = image_bytes(value)
    name = file_name(place, 0, bytes)
    image = ~s|image("#{name}", width: #{pt(place.width)}, height: #{pt(place.height)})|

    markup =
      case place do
        %{level_with: flow} when is_binary(flow) ->
          flow_top = "#{var(flow)}_top"

          [
            "#context place(top + #{across(place)}, ",
            "dy: #{flow_top} + measure(#{var(flow)}).height - #{pt(place.height)}, #{image})\n"
          ]

        _place ->
          "#place(#{at(place)}, #{image})\n"
      end

    {markup, {Map.put(files, name, bytes), values}}
  end

  defp place(%{kind: :tick, value: true} = place, acc) do
    side = place.size
    stroke = pt(side / 10)

    markup = [
      "#place(#{at(place)}, box(width: #{pt(side)}, height: #{pt(side)}, {\n",
      "  place(line(start: (15%, 15%), end: (85%, 85%), stroke: #{stroke}))\n",
      "  place(line(start: (85%, 15%), end: (15%, 85%), stroke: #{stroke}))\n",
      "}))\n"
    ]

    {markup, acc}
  end

  defp place(%{kind: :tick}, acc), do: {"", acc}

  defp place(%{kind: :text, value: text}, acc) when text in [nil, ""], do: {"", acc}

  defp place(%{kind: :text, fit: true} = place, {files, values}) do
    size = pt(size(place))

    # A hair under the width, so a line scaled to it exactly doesn't wrap.
    markup = [
      "#place(#{at(place)}, block(width: #{width(place)}, layout(room => {\n",
      "  set align(left)\n",
      "  set text(size: #{size}, top-edge: #{pt(ascent(place))}, bottom-edge: \"baseline\")\n",
      ~s|  let body = v.at("#{place.name}").join(" ")\n|,
      "  let wide = measure(text(body)).width\n",
      "  text(size: #{size} * calc.min(1, room.width / wide * 0.999), body)\n",
      "})))\n"
    ]

    {markup, {files, Map.put(values, place.name, lines(place.value))}}
  end

  defp place(%{kind: :text, lines: count} = place, {files, values}) do
    # Its height on `count` lines: the first line's ascent, then a pitch for each after.
    height = ascent(place) + (count - 1) * place.pitch + 0.5
    size = pt(size(place))

    markup = [
      "#place(#{at(place)}, block(width: #{width(place)}, layout(room => {\n",
      "  set align(left)\n",
      "  set par(leading: #{pt(gap(place))}, spacing: #{pt(gap(place))})\n",
      ~s|  let body = #{indent(place)}v.at("#{place.name}").join(linebreak())\n|,
      "  let sized(s) = text(size: s, top-edge: #{pt(ascent(place))}, bottom-edge: \"baseline\", body)\n",
      "  let s = #{size}\n",
      "  while s > #{pt(@smallest)} and measure(sized(s), width: room.width).height > #{pt(height)} {\n",
      "    s -= 0.25pt\n",
      "  }\n",
      "  sized(s)\n",
      "})))\n"
    ]

    {markup, {files, Map.put(values, place.name, lines(place.value))}}
  end

  defp place(%{kind: :text} = place, {files, values}) do
    markup = [
      "#place(#{at(place)}, block(width: #{width(place)}, {\n",
      "  set align(left)\n",
      "  set text(size: #{pt(size(place))}, top-edge: #{pt(ascent(place))}, bottom-edge: \"baseline\")\n",
      "  set par(leading: #{pt(gap(place))}, spacing: #{pt(gap(place))})\n",
      ~s|  #{indent(place)}v.at("#{place.name}").join(linebreak())\n|,
      "}))\n"
    ]

    {markup, {files, Map.put(values, place.name, lines(place.value))}}
  end

  defp indent(%{indent: indent}), do: "h(#{pt(indent)}) + "
  defp indent(_place), do: ""

  # A flow down's items, each line a value of the flow's own. A blank line is hidden
  # text, so it's exactly a line's height.
  defp line({{:text, text}, _i}, place, {files, values}) do
    lines = lines(text)

    pars =
      lines
      |> Enum.with_index(length(values[place.name]))
      |> Enum.map(fn {_line, i} -> ~s|  par(v.at("#{place.name}").at(#{i}))\n| end)

    {pars, {files, Map.update!(values, place.name, &(&1 ++ lines))}}
  end

  defp line({{:space, count}, _i}, _place, acc),
    do: {List.duplicate("  par(hide[x])\n", count), acc}

  defp line({{:image, bytes, options}, i}, place, {files, values}) do
    name = file_name(place, i, bytes)
    {width, height} = fit(bytes, options)
    pad = Map.get(options, :pad, 0)

    markup =
      "  block(above: #{pt(pad + gap(place))}, below: #{pt(pad)}, " <>
        "image(\"#{name}\", width: #{pt(width)}, height: #{pt(height)}))\n"

    {markup, {Map.put(files, name, bytes), values}}
  end

  defp lines(text), do: String.split(text, ~r/\r?\n/)

  # Where a place sits: from the page's top or bottom edge, and its left or right.
  defp at(place) do
    {edge, dy} =
      case place do
        %{top: top} -> {"top", top}
        %{bottom: bottom} -> {"bottom", -bottom}
      end

    "#{edge} + #{across(place)}, dy: #{pt(dy)}"
  end

  defp across(%{left: left}), do: "left, dx: #{pt(left)}"
  defp across(%{right: right}), do: "right, dx: #{pt(-right)}"

  # A place's width: its own, or from its left edge to its right.
  defp width(%{width: width}), do: pt(width)

  defp width(place),
    do: "page-width - #{pt(Map.get(place, :left, 0))} - #{pt(Map.get(place, :right, 0))}"

  # The flow's own name, and where it starts, for a place level with it.
  defp var(%{name: name}), do: var(name)
  defp var(name) when is_binary(name), do: "place_#{name}"

  defp size(place), do: Map.get(place, :size, 12)

  # How far the first line's baseline sits below the place's top, as the letters drawn
  # before Typst had it, and the space from one line's baseline to the next line's top:
  # `pitch` or `leading` apart, baseline to baseline.
  defp ascent(place), do: size(place) * 0.75

  defp gap(place),
    do: (Map.get(place, :pitch) || Map.get(place, :leading, size(place) * 1.2)) - ascent(place)

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

  defp pt(points) when is_integer(points), do: "#{points}pt"
  defp pt(points) when is_float(points), do: "#{Float.round(points, 3)}pt"
end
