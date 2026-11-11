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
    starts at its left edge, wherever the place is anchored. With `more`, it shrinks
    only to 8pt; still too long, it says "See attached page", and the PDF ends with a
    letter page of its whole text, headed with its `heading` (#993).
  - A tick is an X across its box, when its condition holds.
  - A flow down is a block of lines, each `leading` below the last. A space is a blank
    line, and a picture is fitted in its box, keeping its shape, with `pad` above and
    below.
  - A flow across is a row of pictures each `height` tall, from its right edge.
  - An image place is a picture, or `{:qr, link}`, a QR code as an SVG from EQRCode.
    `level with` puts its bottom edge level with a flow's last line.

  A form's page is `page.pdf`. Each of its pages prints at its own size, with the
  places that say that page drawn over it, once for each copy a form's rows need. A
  place on a later copy keeps its values under its own key, `subtotal-copy2`.

  A published PDF's verify code (#970) prints on every page, since an agency may
  separate them: in a corner, half an inch from its edges, the QR code of its verify
  link in capitals, which fits a version 3 code, then "Verify this document" and the
  link. The document's `verify code` moves it or trims it. A draft prints a grey box in
  its place, so a team admin can check the layout before publishing.

  A form with a layout has no places (#950): its Typst layout follows a few lines that
  read `values.json` as `values` and set the font, and it lays the page out itself.
  It's `values`, not `v`, so the layout keeps Typst's `v()` for space. Each value is
  there by its name, as text, true or false, or `none` for a blank: `values.claimant`.
  A picture is a file the layout reads by the name it holds,
  `image(values.signature)`, and a `fill each` is an array of dictionaries.
  """

  @letter_width 612
  @letter_height 792
  # An attached page's header: its heading and which of its pages this is, counted from
  # the metadata at its text's start and end (#993). A long team name wraps it, so
  # attached-top measures it at its longest, "page 99 of 99", and the text starts below.
  @attached_header """
  #let attached-heading(body) = text(size: 12pt, weight: "bold", body)
  #let attached-top(heading) = measure(
    block(width: #{@letter_width - 144}pt, attached-heading(heading + ", page 99 of 99"))
  ).height
  #let attached-header(heading, more) = context {
    let start = query(metadata.where(value: more + "-start"))
    let end = query(metadata.where(value: more + "-end"))
    let (n, count) = (1, 1)
    if start.len() > 0 and end.len() > 0 {
      let first = start.first().location().page()
      n = here().page() - first + 1
      count = end.first().location().page() - first + 1
    }
    attached-heading(heading + ", page " + str(n) + " of " + str(count))
  }
  """

  # The smallest size a text on its `lines` shrinks to, and one that goes on an attached
  # page when it's still too long (#993): 6pt is too small for a page someone signs.
  @smallest 6
  @smallest_more 8

  @doc """
  `{markup, files}`: the Typst source, and each file it reads by name. `mark` is a
  picture drawn over each page, such as SAMPLE for a Try a demo team (#857). `page` is `{pdf, pages}`,
  a form's page and how many pages it has; without it the page is letter paper.
  `verify` is a published PDF's verify link, or `:draft` for a draft's grey box; without
  it no verify code prints.
  """
  def typst(output, opts \\ [])

  def typst(%{layout: %{text: layout}} = output, opts) do
    files = mark_file(%{}, Keyword.get(opts, :mark))
    {values, files} = layout_values(output.fills, files)
    values = Map.merge(values, %{"title" => output.title, "author" => output.author})

    {verify, {files, values}} =
      verify_code(output, Keyword.get(opts, :verify), "values", files, values)

    markup =
      IO.iodata_to_binary([
        ~s|#let values = json("values.json")\n|,
        document("values", values),
        ~s|#set text(font: "Arimo", fallback: false)\n|,
        verify,
        foreground(files, verify),
        layout
      ])

    {markup, Map.put(files, "values.json", Jason.encode!(values))}
  end

  def typst(output, opts) do
    files = mark_file(%{}, Keyword.get(opts, :mark))
    page = Keyword.get(opts, :page)
    files = if page, do: Map.put(files, "page.pdf", elem(page, 0)), else: files
    values = %{"title" => output.title, "author" => output.author}

    {verify, {files, values}} =
      verify_code(output, Keyword.get(opts, :verify), "v", files, values)

    {pages, {files, values}} = pages(output, page, files, values, verify != "")
    {attached, values} = attached(output.places, files, values, verify != "")

    markup =
      IO.iodata_to_binary([
        ~s|#let v = json("values.json")\n|,
        document("v", values),
        ~s|#set text(font: "Arimo", fallback: false)\n|,
        verify,
        pages,
        attached
      ])

    {markup, Map.put(files, "values.json", Jason.encode!(values))}
  end

  # Each page of each copy, with the places on it, then the verify code and the mark.
  defp pages(output, page, files, values, verify?) do
    for(copy <- 1..Map.get(output, :copies, 1), n <- page_numbers(page), do: {copy, n})
    |> Enum.map_reduce({files, values}, fn {copy, n}, acc ->
      {body, acc} = output.places |> on_page(copy, n) |> Enum.map_reduce(acc, &place/2)
      verify = if verify?, do: "#verify-code\n", else: ""
      {page_markup(n, page, [body, verify, mark(files)]), acc}
    end)
  end

  # Pages at the end for each place that says `more` and was too long for its lines
  # (#993): the whole text on plain letter paper, a line apart from the next, under a
  # header on every page with its heading and "page 1 of 3", so a loose page still says
  # what it belongs to. The place set its state when it printed "See attached page", so
  # Typst decides, and a text that fits adds no page. The verify code and the mark print
  # on it as on every other page.
  defp attached(places, files, values, verify?) do
    places
    |> Enum.filter(&(Map.has_key?(&1, :more) and copy(&1) == 1 and &1.value not in [nil, ""]))
    |> Enum.map_reduce(values, fn place, values ->
      heading = "#{place.name}-heading"
      more = more_state(place)

      markup = [
        ~s|#context if state("#{more}", false).final() {\n|,
        "  page(width: #{pt(@letter_width)}, height: #{pt(@letter_height)}, ",
        ~s|margin: (x: 1in, top: 0.75in + attached-top(v.at("#{heading}")) + 18pt, |,
        "bottom: 1.5in), header-ascent: 18pt, ",
        ~s|header: align(bottom, attached-header(v.at("#{heading}"), "#{more}")), |,
        "foreground: {#{attached_foreground(files, verify?)}}, {\n",
        "    set text(size: 11pt)\n",
        "    set par(spacing: 6pt)\n",
        ~s|    metadata("#{more}-start")\n|,
        ~s|    v.at("#{place.name}").join(parbreak())\n|,
        ~s|    metadata("#{more}-end")\n|,
        "  })\n",
        "}\n"
      ]

      {markup, Map.put(values, heading, place.heading)}
    end)
    |> then(fn
      {[], values} -> {[], values}
      {markup, values} -> {[@attached_header | markup], values}
    end)
  end

  defp attached_foreground(files, verify?) do
    [
      if(verify?, do: "verify-code"),
      if(Map.has_key?(files, "mark.png"),
        do: ~s|place(top + left, image("mark.png", width: 100%))|
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
  end

  defp more_state(place), do: "more-#{place.name}"

  defp on_page(places, copy, n),
    do: Enum.filter(places, &(Map.get(&1, :page, 1) == n and copy(&1) == copy))

  defp page_numbers(nil), do: [1]
  defp page_numbers({_pdf, pages}), do: Enum.to_list(1..pages)

  defp document(var, values) do
    case Enum.filter(["title", "author"], &(values[&1] not in [nil, ""])) do
      [] -> ""
      names -> "#set document(#{Enum.map_join(names, ", ", &"#{&1}: #{var}.at(\"#{&1}\")")})\n"
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

  defp mark_file(files, nil), do: files
  defp mark_file(files, png), do: Map.put(files, "mark.png", png)

  defp mark(%{"mark.png" => _}),
    do: ~s|#place(top + left, image("mark.png", width: page-width))\n|

  defp mark(_files), do: ""

  # A layout sets its own pages, so the verify code and the mark are each page's
  # foreground.
  defp foreground(files, verify) do
    parts =
      [
        if(verify != "", do: "verify-code"),
        if(Map.has_key?(files, "mark.png"),
          do: ~s|place(top + left, image("mark.png", width: 100%))|
        )
      ]
      |> Enum.reject(&is_nil/1)

    if parts == [],
      do: "",
      else: "#set page(foreground: {#{Enum.join(parts, "; ")}})\n"
  end

  # The verify code as `#let verify-code`, which each page places, and the files and
  # values it reads: `{markup, {files, values}}`, or "" when nothing prints.
  # cspell:ignore luma -- Typst's grey
  @verify_margin 36
  @verify_qr 50
  @verify_size 8

  defp verify_code(%{verify_code: %{at: at, show: show}}, verify, var, files, values)
       when verify != nil do
    {qr, link, files, values} = verify_parts(verify, show, var, files, values)

    # The QR code sits in the corner, with the words on the page's side of it.
    parts = if at in [:top_right, :bottom_right], do: [link, qr], else: [qr, link]
    body = parts |> Enum.reject(&(&1 == nil)) |> Enum.join(", ")

    {edge, dy} =
      if at in [:top_left, :top_right],
        do: {"top", @verify_margin},
        else: {"bottom", -@verify_margin}

    {side, dx} =
      if at in [:top_left, :bottom_left],
        do: {"left", @verify_margin},
        else: {"right", -@verify_margin}

    markup = [
      "#let verify-code = place(#{edge} + #{side}, dx: #{pt(dx)}, dy: #{pt(dy)}, ",
      "stack(dir: ltr, spacing: 6pt, #{body}))\n"
    ]

    {markup, {files, values}}
  end

  defp verify_code(_output, _verify, _var, files, values), do: {"", {files, values}}

  # A draft's grey box, as big as what will print there.
  defp verify_parts(:draft, show, _var, files, values) do
    {width, height} =
      case show do
        :qr -> {@verify_qr, @verify_qr}
        :link -> {150, 20}
        :both -> {@verify_qr + 156, @verify_qr}
      end

    box = [
      "box(width: #{pt(width)}, height: #{pt(height)}, fill: luma(225), inset: 4pt, ",
      "align(horizon + center, text(size: #{pt(@verify_size)}, fill: luma(80))",
      "[The verify code prints here when this is published.]))"
    ]

    {IO.iodata_to_binary(box), nil, files, values}
  end

  defp verify_parts(link, show, var, files, values) when is_binary(link) do
    qr =
      if show in [:both, :qr],
        do: ~s|image("verify-qr.svg", width: #{pt(@verify_qr)}, height: #{pt(@verify_qr)})|

    words =
      if show in [:both, :link],
        do:
          "align(horizon, stack(spacing: 4pt, " <>
            ~s|text(size: #{pt(@verify_size)}, weight: "bold")[Verify this document], | <>
            ~s|text(size: #{pt(@verify_size)}, #{var}.at("verify-link"))))|

    files =
      if qr,
        do: Map.put(files, "verify-qr.svg", image_bytes({:qr, String.upcase(link)})),
        else: files

    shown = String.replace(link, ~r{\Ahttps?://}, "")
    {qr, words, files, Map.put(values, "verify-link", shown)}
  end

  # A layout's values: each picture a file, by its value's name, and the rest as they are.
  defp layout_values(fills, files) do
    Enum.reduce(fills, {%{}, files}, fn
      {name, {:image, picture}}, {values, files} ->
        bytes = image_bytes(picture)
        file = "#{name}.#{extension(bytes)}"
        {Map.put(values, name, file), Map.put(files, file, bytes)}

      {name, value}, {values, files} ->
        {Map.put(values, name, value), files}
    end)
  end

  @doc """
  Whether a text place that says `more` is likely too long for its lines, from its
  text's length (#993), so a form's page can warn before it prints. Typst decides when
  it prints; this guesses the same from Arimo's average letter, 0.47 of its size at
  8pt, and starts a line at each of the text's own line breaks.
  """
  def attached?(%{more: _, lines: count, value: text} = place) when is_binary(text) do
    per_line = max(1, floor(text_width(place) / (@smallest_more * 0.47)))
    indent = ceil(Map.get(place, :indent, 0) / (@smallest_more * 0.47))

    needed =
      text
      |> lines()
      |> List.update_at(0, &(String.duplicate(" ", indent) <> &1))
      |> Enum.map(&max(1, ceil(String.length(&1) / per_line)))
      |> Enum.sum()

    needed > count
  end

  def attached?(_place), do: false

  defp text_width(%{width: width}), do: width
  defp text_width(place), do: @letter_width - Map.get(place, :left, 0) - Map.get(place, :right, 0)

  @doc """
  A Typst error on a form's layout, with each `main.typ:12:5:` read as the line of the
  form's text it's on: `Line 140:`. `markup` is what `typst/2` gave.
  """
  def layout_error(reason, markup, %{layout: %{text: layout, line: line}}) do
    # The lines before the layout's first.
    before = newlines(markup) - newlines(layout)

    reason
    |> String.replace(~r/\ATypst stopped with status \d+: /, "")
    |> then(
      &Regex.replace(~r/main\.typ:(\d+):\d+: (?:error: )?/, &1, fn _all, at ->
        "Line #{String.to_integer(at) - before + line - 1}: "
      end)
    )
  end

  defp newlines(text), do: text |> String.split("\n") |> length()

  # Places, each `{markup, {files, values}}`

  defp place(%{kind: :flow, across: false} = place, {files, values}) do
    {items, {files, values}} =
      place.value
      |> Enum.with_index()
      |> Enum.map_reduce({files, Map.put(values, key(place), [])}, &line(&1, place, &2))

    markup = [
      "#let #{var(place)} = block(width: #{width(place)}, {\n",
      "  set align(#{align(place)})\n",
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
      "  set align(#{align(place)})\n",
      "  set text(size: #{size}, top-edge: #{pt(ascent(place))}, bottom-edge: \"baseline\")\n",
      ~s|  let body = v.at("#{key(place)}").join(" ")\n|,
      "  let wide = measure(text(body)).width\n",
      "  text(size: #{size} * calc.min(1, room.width / wide * 0.999), body)\n",
      "})))\n"
    ]

    {markup, {files, Map.put(values, key(place), lines(place.value))}}
  end

  defp place(%{kind: :text, lines: count} = place, {files, values}) do
    # Its height on `count` lines: the first line's ascent, then a pitch for each after.
    height = ascent(place) + (count - 1) * place.pitch + 0.5
    size = pt(size(place))
    smallest = if Map.has_key?(place, :more), do: @smallest_more, else: @smallest

    markup = [
      "#place(#{at(place)}, block(width: #{width(place)}, layout(room => {\n",
      "  set align(#{align(place)})\n",
      "  set par(leading: #{pt(gap(place))}, spacing: #{pt(gap(place))})\n",
      ~s|  let body = #{indent(place)}v.at("#{key(place)}").join(linebreak())\n|,
      "  let sized(s) = text(size: s, top-edge: #{pt(ascent(place))}, bottom-edge: \"baseline\", body)\n",
      "  let s = #{size}\n",
      "  while s > #{pt(smallest)} and measure(sized(s), width: room.width).height > #{pt(height)} {\n",
      "    s -= 0.25pt\n",
      "  }\n",
      more_or_sized(place, height),
      "})))\n"
    ]

    {markup, {files, Map.put(values, key(place), lines(place.value))}}
  end

  defp place(%{kind: :text} = place, {files, values}) do
    markup = [
      "#place(#{at(place)}, block(width: #{width(place)}, {\n",
      "  set align(#{align(place)})\n",
      "  set text(size: #{pt(size(place))}, top-edge: #{pt(ascent(place))}, bottom-edge: \"baseline\")\n",
      "  set par(leading: #{pt(gap(place))}, spacing: #{pt(gap(place))})\n",
      ~s|  #{indent(place)}v.at("#{key(place)}").join(linebreak())\n|,
      "}))\n"
    ]

    {markup, {files, Map.put(values, key(place), lines(place.value))}}
  end

  # Still too long at 8pt, a place that says `more` prints "See attached page" on its
  # first line and sets its state, so the attached page prints at the end (#993).
  defp more_or_sized(%{more: _} = place, height) do
    [
      "  if measure(sized(s), width: room.width).height > #{pt(height)} {\n",
      ~s|    state("#{more_state(place)}", false).update(true)\n|,
      "    text(size: #{pt(size(place))}, top-edge: #{pt(ascent(place))}, bottom-edge: \"baseline\", ",
      "#{indent(place)}[See attached page])\n",
      "  } else {\n",
      "    sized(s)\n",
      "  }\n"
    ]
  end

  defp more_or_sized(_place, _height), do: "  sized(s)\n"

  # A place's values key and file names: its name, and on a later copy of a form's page,
  # which copy, since each copy fills the same place with its own values.
  defp key(place) do
    case copy(place) do
      1 -> place.name
      copy -> "#{place.name}-copy#{copy}"
    end
  end

  defp copy(place), do: Map.get(place, :copy, 1)

  defp align(place), do: place |> Map.get(:align, :left) |> Atom.to_string()

  defp indent(%{indent: indent}), do: "h(#{pt(indent)}) + "
  defp indent(_place), do: ""

  # A flow down's items, each line a value of the flow's own. A blank line is hidden
  # text, so it's exactly a line's height.
  defp line({{:text, text}, _i}, place, {files, values}) do
    lines = lines(text)

    pars =
      lines
      |> Enum.with_index(length(values[key(place)]))
      |> Enum.map(fn {_line, i} -> ~s|  par(v.at("#{key(place)}").at(#{i}))\n| end)

    {pars, {files, Map.update!(values, key(place), &(&1 ++ lines))}}
  end

  # A typed signature (#995): /s/ and the name in Dancing Script, bold, on a line of its
  # own with 6 points above and below. A letter the script lacks falls back to Arimo.
  defp line({{:signature, text}, _i}, place, {files, values}) do
    i = length(values[key(place)])

    markup =
      "  block(above: #{pt(6 + gap(place))}, below: 6pt, " <>
        ~s|text(font: ("Dancing Script", "Arimo"), weight: 700, size: 16pt, fill: black, | <>
        ~s|top-edge: "ascender", bottom-edge: "descender", v.at("#{key(place)}").at(#{i})))\n|

    {markup, {files, Map.update!(values, key(place), &(&1 ++ lines(text)))}}
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

  defp file_name(place, i, bytes), do: "#{key(place)}-#{i}.#{extension(bytes)}"

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
