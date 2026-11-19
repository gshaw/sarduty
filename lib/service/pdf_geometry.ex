defmodule Service.PDFGeometry do
  @moduledoc """
  What's printed where on a form's page (#1083), so a model writing a team's form
  writes each place from measured points instead of guessing them from a picture.
  MuPDF's `mutool` reads the PDF, through Service.Program, and every length is in points
  from the page's top left, as a form's places are:

  - `lines`: each line of text, with its left and right ends, its top, its baseline, and
    its font size.
  - `blanks`: each run of underscores, as Word prints a form's lines, with its ends and
    the baseline it sits on.
  - `rules`: each drawn line across the page, with its ends and the `y` of its top edge.
  - `boxes`: each drawn rectangle, such as a box to tick or a box to write in.

  It reads only what the PDF draws: a scan has no lines of text, and a fillable PDF's own
  boxes are not read. It's MuPDF's text and path output, read line by line, not a
  general PDF reader.
  """

  # cspell:ignore stext apos -- MuPDF's output and XML names

  @timeout_ms 20_000
  @max_pages 20

  # A drawn line is at most this thick, and a box or a rule at least this long.
  @thin 3.0
  @long 8.0

  @type page :: %{
          number: pos_integer(),
          width: float(),
          height: float(),
          lines: [map()],
          blanks: [map()],
          rules: [map()],
          boxes: [map()]
        }

  @doc "The path of mutool, or nil when this machine has none."
  def executable, do: System.find_executable("mutool")

  @doc """
  `{:ok, pages}`, the first #{@max_pages} pages of `pdf`, or `{:error, reason}`.
  """
  def read(pdf) when is_binary(pdf) do
    dir = Service.Temp.path()
    File.mkdir_p!(dir)

    try do
      dir |> Path.join("in.pdf") |> File.write!(pdf)
      range = "1-#{@max_pages}"

      with {:ok, _} <- mutool(~w(draw -q -F stext -o text.xml in.pdf #{range}), dir),
           {:ok, _} <- mutool(~w(draw -q -F trace -o paths.xml in.pdf #{range}), dir) do
        text = dir |> Path.join("text.xml") |> File.read!() |> read_text()
        paths = dir |> Path.join("paths.xml") |> File.read!() |> read_paths()
        {:ok, pages(text, paths)}
      end
    after
      File.rm_rf(dir)
    end
  end

  @doc """
  `pages` from `read/1` written out for a model writing a form's places (#1088): each
  page's size, then its lines of text, blanks, rules, and boxes, one a line, in points
  from the page's top left.
  """
  def describe(pages) when is_list(pages), do: Enum.map_join(pages, "\n", &describe_page/1)

  defp describe_page(page) do
    [
      "Page #{page.number}: #{pt(page.width)} wide and #{pt(page.height)} high.",
      list("Lines of text", page.lines, [:x0, :x1, :top, :baseline, :size, :text]),
      list("Blanks, runs of underscores", page.blanks, [:x0, :x1, :baseline]),
      list("Rules, drawn lines", page.rules, [:x0, :x1, :y]),
      list("Boxes", page.boxes, [:x0, :x1, :top, :bottom])
    ]
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp list(title, [], _keys), do: "#{title}: none."

  defp list(title, items, keys) do
    rows =
      Enum.map_join(items, "\n", fn item ->
        Enum.map_join(keys, " ", fn
          :text -> inspect(item.text)
          key -> pt(Map.fetch!(item, key))
        end)
      end)

    "#{title} (#{Enum.join(keys, " ")}):\n#{rows}"
  end

  defp pt(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 1)
  defp pt(value), do: to_string(value)

  defp mutool(args, dir) do
    case Service.Program.run(executable(), args, dir, "mutool", @timeout_ms) do
      {:ok, output} -> {:ok, output}
      {:error, _reason} -> {:error, "SAR Duty cannot read this PDF's page."}
    end
  end

  defp pages(text, paths) do
    for {number, page} <- Enum.sort(text) do
      shapes = Map.get(paths, number, %{rules: [], boxes: []})

      Map.merge(page, %{
        number: number,
        lines: Enum.reverse(page.lines),
        blanks: Enum.reverse(page.blanks),
        rules: shapes.rules |> Enum.uniq() |> Enum.sort_by(&{&1.y, &1.x0}),
        boxes: shapes.boxes |> Enum.uniq() |> Enum.sort_by(&{&1.top, &1.x0})
      })
    end
  end

  # Each line of MuPDF's XML is one tag: its name, and its attributes, unescaped.
  defp tags(xml) do
    for line <- String.split(xml, "\n"),
        [_, name] <- [Regex.run(~r/^\s*<(\/?[a-z_]+)/, line)],
        do: {name, line}
  end

  # Text: `<page width height>`, then `<line>`s of `<font size>`s of `<char>`s.

  @doc false
  def read_text(xml) do
    {pages, _state} =
      xml |> tags() |> Enum.reduce({%{}, %{page: 0, size: nil, chars: []}}, &text_tag/2)

    pages
  end

  defp text_tag({"page", line}, {pages, state}) do
    attrs = attrs(line)

    page = %{
      width: number(attrs["width"]),
      height: number(attrs["height"]),
      lines: [],
      blanks: []
    }

    {Map.put(pages, state.page + 1, page), %{state | page: state.page + 1, chars: []}}
  end

  defp text_tag({"line", _line}, {pages, state}), do: {pages, %{state | chars: []}}

  defp text_tag({"font", line}, {pages, state}),
    do: {pages, %{state | size: number(attrs(line)["size"])}}

  defp text_tag({"char", line}, {pages, state}),
    do: {pages, %{state | chars: [char(attrs(line), state.size) | state.chars]}}

  defp text_tag({"/line", _line}, {pages, state}) do
    chars = Enum.reverse(state.chars)
    {Map.update!(pages, state.page, &add_line(&1, chars)), state}
  end

  defp text_tag(_tag, acc), do: acc

  defp char(attrs, size) do
    [x0, top, x1 | _rest] = attrs["quad"] |> String.split() |> Enum.map(&number/1)
    %{c: attrs["c"], x0: x0, x1: x1, top: top, baseline: number(attrs["y"]), size: size}
  end

  defp add_line(page, []), do: page

  defp add_line(page, chars) do
    page = %{page | blanks: (chars |> blanks() |> Enum.reverse()) ++ page.blanks}

    case chars |> Enum.map_join(& &1.c) |> String.trim() do
      "" -> page
      text -> %{page | lines: [line(text, chars) | page.lines]}
    end
  end

  defp line(text, [first | _rest] = chars) do
    %{
      text: text,
      x0: round1(first.x0),
      x1: chars |> Enum.map(& &1.x1) |> Enum.max() |> round1(),
      top: chars |> Enum.map(& &1.top) |> Enum.min() |> round1(),
      baseline: round1(first.baseline),
      size: round1(first.size || 0.0)
    }
  end

  # Runs of underscores, two or more, as a blank to write on.
  defp blanks(chars) do
    chars
    |> Enum.chunk_by(&(&1.c == "_"))
    |> Enum.filter(fn run -> length(run) > 1 and hd(run).c == "_" end)
    |> Enum.map(fn run ->
      %{
        x0: round1(hd(run).x0),
        x1: round1(List.last(run).x1),
        baseline: round1(hd(run).baseline)
      }
    end)
  end

  # Paths: `<page>`, then `<fill_path>` and `<stroke_path>` of `<moveto>` and `<lineto>`
  # points in the path's own space, with its `transform` to the page's. Pages count in
  # order, as text's do: older MuPDF, such as Debian trixie's 1.25 in production and
  # Ubuntu 24.04's 1.23 in CI, writes no `number` on `<page>`.

  @doc false
  def read_paths(xml) do
    {pages, _state} = xml |> tags() |> Enum.reduce({%{}, %{page: 0, path: nil}}, &path_tag/2)
    pages
  end

  defp path_tag({"page", _line}, {pages, state}) do
    number = state.page + 1
    {Map.put(pages, number, %{rules: [], boxes: []}), %{state | page: number}}
  end

  defp path_tag({kind, line}, {pages, state}) when kind in ["fill_path", "stroke_path"],
    do: {pages, %{state | path: new_path(kind, attrs(line))}}

  defp path_tag({"moveto", line}, {pages, %{path: %{} = path} = state}),
    do: {pages, %{state | path: move_to(path, point(line, path.transform))}}

  defp path_tag({"lineto", line}, {pages, %{path: %{} = path} = state}),
    do: {pages, %{state | path: line_to(path, point(line, path.transform))}}

  defp path_tag({kind, _line}, {pages, %{path: %{} = path} = state})
       when kind in ["/fill_path", "/stroke_path"],
       do: {Map.update!(pages, state.page, &add_shapes(&1, path)), %{state | path: nil}}

  defp path_tag(_tag, acc), do: acc

  defp new_path(kind, attrs) do
    [a, b, c, d, _e, _f] = transform = transform(attrs["transform"])
    scale = (a * d - b * c) |> abs() |> :math.sqrt()

    %{
      kind: if(kind == "fill_path", do: :fill, else: :stroke),
      white?: white?(attrs["color"]),
      width: number(attrs["linewidth"] || "0") * scale,
      transform: transform,
      subpaths: []
    }
  end

  defp transform(nil), do: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
  defp transform(text), do: text |> String.split() |> Enum.map(&number/1)

  # A white or nearly white path is a page's background, never a line to write on.
  defp white?(nil), do: false
  defp white?(color), do: color |> String.split() |> Enum.all?(&(number(&1) > 0.9))

  defp point(line, [a, b, c, d, e, f]) do
    attrs = attrs(line)
    {x, y} = {number(attrs["x"]), number(attrs["y"])}
    {a * x + c * y + e, b * x + d * y + f}
  end

  defp move_to(path, point), do: %{path | subpaths: [[point] | path.subpaths]}
  defp line_to(%{subpaths: []} = path, point), do: move_to(path, point)

  defp line_to(%{subpaths: [s | rest]} = path, point),
    do: %{path | subpaths: [[point | s] | rest]}

  defp add_shapes(shapes, %{white?: true}), do: shapes

  defp add_shapes(shapes, path) do
    for points <- path.subpaths,
        shape <- shapes_of(path, Enum.reverse(points)),
        reduce: shapes do
      acc ->
        case shape do
          {:rule, rule} -> %{acc | rules: [rule | acc.rules]}
          {:box, box} -> %{acc | boxes: [box | acc.boxes]}
        end
    end
  end

  # A thin filled rectangle is a rule, and a bigger one a box. A stroked path is a box
  # when it closes round an area, and otherwise each of its long level lines is a rule.
  defp shapes_of(_path, [_one]), do: []
  defp shapes_of(%{kind: :fill}, points), do: points |> bounds() |> filled()

  defp shapes_of(%{kind: :stroke, width: width}, points) do
    {x0, top, x1, bottom} = bounds = bounds(points)

    if bottom - top > @thin and x1 - x0 > @thin and length(points) >= 4,
      do: [{:box, box(bounds)}],
      else: stroked_rules(points, width)
  end

  defp filled({x0, top, x1, bottom} = bounds) do
    {width, height} = {x1 - x0, bottom - top}

    cond do
      width < @long and height < @long -> []
      height <= @thin -> [{:rule, rule(x0, x1, top)}]
      width <= @thin -> []
      true -> [{:box, box(bounds)}]
    end
  end

  defp stroked_rules(points, width) do
    for [{ax, ay}, {bx, by}] <- Enum.chunk_every(points, 2, 1, :discard),
        abs(ay - by) < 0.5 and abs(ax - bx) >= @long,
        do: {:rule, rule(min(ax, bx), max(ax, bx), ay - width / 2)}
  end

  defp bounds(points) do
    {xs, ys} = Enum.unzip(points)
    {Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)}
  end

  defp rule(x0, x1, y), do: %{x0: round1(x0), x1: round1(x1), y: round1(y)}

  defp box({x0, top, x1, bottom}),
    do: %{x0: round1(x0), x1: round1(x1), top: round1(top), bottom: round1(bottom)}

  # XML attributes, unescaped.

  defp attrs(line) do
    ~r/([a-z_]+)="([^"]*)"/
    |> Regex.scan(line, capture: :all_but_first)
    |> Map.new(fn [name, value] -> {name, unescape(value)} end)
  end

  defp unescape(value) do
    value
    |> String.replace(~r/&#x([0-9a-fA-F]+);/, fn entity ->
      code = entity |> String.slice(3..-2//1) |> String.to_integer(16)
      <<code::utf8>>
    end)
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
  end

  # MuPDF writes ".6" and "-.5" for 0.6 and -0.5.
  defp number(nil), do: 0.0

  defp number(text) do
    text = text |> String.trim() |> String.replace(~r/^(-?)\./, "\\g{1}0.")

    case Float.parse(text) do
      {value, _rest} -> value
      :error -> 0.0
    end
  end

  defp round1(value), do: Float.round(value * 1.0, 1)
end
