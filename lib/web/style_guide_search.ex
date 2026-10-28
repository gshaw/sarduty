defmodule Web.StyleGuideSearch do
  @moduledoc """
  The style guide's search: every page in `Web.StyleGuideHTML.groups/0`, rendered as a
  browser gets it, split into sections at its headings. Nobody writes the index, so it
  holds what each page says, examples included. Production builds it on the first search
  and keeps it until the next deploy; development builds it on every search. See
  docs/search.md.
  """

  alias Web.StyleGuideHTML

  @per_group 5
  @snippet 110
  @recent 5

  # Text people don't read, and the links in a demo's own top bar.
  @skipped ~w(script style template head)
  # Inline elements join the text around them, so "<code>tel:</code> link" stays one line.
  @inline ~w(a abbr b code em i kbd mark s small span strong sub sup time u)

  @doc """
  The index, one entry per section: the lead, before the first heading, then one per
  `h2` or `h3` outside an example.
  """
  def index do
    if Application.get_env(:sarduty, :style_guide_search_cache, true) do
      case :persistent_term.get(__MODULE__, nil) do
        nil ->
          index = build()
          :persistent_term.put(__MODULE__, index)
          index

        index ->
          index
      end
    else
      build()
    end
  end

  @doc "Builds the index from every page's HTML."
  def build do
    for {group, group_title, _about, pages} <- StyleGuideHTML.groups(),
        {page, title, about} <- pages,
        entry <- page |> render() |> sections(%{page: page, title: title, about: about}) do
      Map.merge(entry, %{group: group, group_title: group_title})
    end
  end

  @doc "A page's HTML, as the controller renders it inside the guide's frame."
  def render(page) do
    StyleGuideHTML
    |> apply(StyleGuideHTML.template(page), [%{current: page}])
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  @doc """
  Pure. A page's HTML in sections, `%{id, heading, text, path, …}`, the lead first with no
  heading. Everything before the guide's `main` is kept only to make each heading's link
  unique.
  """
  def sections(html, page) do
    document = Floki.parse_document!(html)
    before = document |> Floki.find(".side-nav") |> text_of() |> normalize()
    [{nil, lead} | headed] = document |> events() |> split()
    slug = page.page |> Atom.to_string() |> String.replace("_", "-")

    {entries, _seen} =
      Enum.map_reduce(headed, Enum.join([before, page.title, lead], " "), &headed(&1, &2, page))

    [entry(page, slug, nil, lead, "") | Enum.reject(entries, &(&1.heading == ""))]
  end

  # A section under a heading, and the page's text up to its end.
  defp headed({heading, text}, seen, page) do
    slug = page.page |> Atom.to_string() |> String.replace("_", "-")

    entry =
      entry(page, slug <> "--" <> slugify(heading), heading, text, fragment(heading, text, seen))

    {entry, Enum.join([seen, heading, text], " ")}
  end

  # The guide's main column, without its breadcrumbs, as headings and text.
  defp events(document) do
    document
    |> Floki.find("main.guide-main")
    |> Enum.flat_map(fn {_tag, _attrs, children} -> children end)
    |> Enum.reject(&breadcrumbs?/1)
    |> walk(false)
  end

  # [{heading, text}], the lead's heading nil.
  defp split(events) do
    events
    |> Enum.reduce([{nil, []}], fn
      {:heading, heading}, sections -> [{heading, []} | sections]
      {:text, text}, [{heading, texts} | rest] -> [{heading, [text | texts]} | rest]
    end)
    |> Enum.reverse()
    |> Enum.map(fn {heading, texts} ->
      {heading, texts |> Enum.reverse() |> IO.iodata_to_binary() |> normalize()}
    end)
  end

  defp breadcrumbs?({"ol", attrs, _children}), do: {"class", "breadcrumbs"} in attrs
  defp breadcrumbs?(_node), do: false

  defp entry(page, id, heading, text, fragment) do
    %{
      id: id,
      page: page.page,
      title: page.title,
      about: page.about,
      heading: heading,
      text: text,
      path: StyleGuideHTML.page_path(page.page) <> fragment
    }
  end

  # Headings in an example (.demo or .example) are the example's, not the page's.
  defp walk(nodes, in_demo?) when is_list(nodes), do: Enum.flat_map(nodes, &walk(&1, in_demo?))
  defp walk(text, _in_demo?) when is_binary(text), do: [{:text, text}]
  defp walk({tag, _attrs, _children}, _in_demo?) when tag in @skipped, do: []

  defp walk({tag, _attrs, children}, false) when tag in ["h2", "h3"],
    do: [{:heading, children |> text_of() |> normalize()}]

  defp walk({tag, attrs, children}, in_demo?) do
    in_demo? = in_demo? or demo?(attrs)
    inner = walk(children, in_demo?)
    if tag in @inline, do: inner, else: [{:text, " "} | inner] ++ [{:text, " "}]
  end

  defp walk(_comment, _in_demo?), do: []

  defp demo?(attrs) do
    case List.keyfind(attrs, "class", 0) do
      {"class", class} -> class |> String.split() |> Enum.any?(&(&1 in ["demo", "example"]))
      nil -> false
    end
  end

  defp text_of(nodes) do
    nodes
    |> walk(true)
    |> Enum.map(fn {:text, text} -> text end)
    |> IO.iodata_to_binary()
  end

  defp normalize(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp slugify(text),
    do: text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")

  # A text fragment opens the page at the heading, so headings need no ids. When the
  # heading's words show earlier on the page, the words after it pick the right one.
  defp fragment("", _text, _seen), do: ""

  defp fragment(heading, text, seen) do
    suffix =
      if match?([_ | _], word_matches(String.downcase(seen), String.downcase(heading))),
        do: text |> String.split(" ", trim: true) |> Enum.take(3) |> Enum.join(" "),
        else: ""

    "#:~:text=" <> encode(heading) <> if(suffix != "", do: ",-" <> encode(suffix), else: "")
  end

  # Text directives reserve "-", "," and "&" as well.
  defp encode(text), do: URI.encode(text, &(URI.char_unreserved?(&1) and &1 != ?-))

  @doc """
  Pure. The results for `query`, grouped as the top bar's search groups them, from
  `entries` (`index/0`). Every word typed must start a word of the page title, the
  section's heading, or its text. A match in a page title ranks first, then in a heading,
  then in the text.
  """
  def run(query, entries \\ index()) do
    case App.ViewData.Search.terms(query) do
      [] ->
        []

      terms ->
        entries
        |> Enum.with_index()
        |> Enum.flat_map(&hit(&1, terms))
        |> Enum.sort_by(& &1.rank)
        |> Enum.group_by(& &1.group)
        |> Enum.sort_by(fn {_group, [best | _hits]} -> best.rank end)
        |> Enum.map(&group/1)
    end
  end

  defp group({group, [best | _rest] = hits}) do
    %{
      kind: group,
      heading: best.group_title,
      more?: false,
      hits:
        hits |> Enum.take(@per_group) |> Enum.map(&Map.drop(&1, [:group, :group_title, :rank]))
    }
  end

  defp hit({entry, order}, terms) do
    case tier(entry, terms) do
      nil ->
        []

      {tier, field, line} ->
        rank = {tier, closeness(field, Enum.join(terms, " ")), order}

        [
          entry
          |> shown(line)
          |> Map.merge(%{group: entry.group, group_title: entry.group_title, rank: rank})
        ]
    end
  end

  # {tier, the field that matched, the line under the title}: 0 the page title, 1 a
  # heading, 2 the text. A section found by its page's title alone is left to the page.
  defp tier(entry, terms) do
    title? = all?(entry.title, terms)

    cond do
      entry.heading == nil and title? ->
        {0, entry.title, entry.about}

      title? ->
        nil

      entry.heading && all?(entry.title <> " " <> entry.heading, terms) ->
        {1, entry.heading, start(entry.text)}

      all?(Enum.join([entry.title, entry.heading, entry.text], " "), terms) ->
        {2, entry.text, snippet(entry.text, terms)}

      true ->
        nil
    end
  end

  # A hit as Web.Components.Search shows it.
  defp shown(entry, line) do
    %{
      kind: if(entry.heading, do: :section, else: :page),
      id: entry.id,
      title: title(entry),
      path: entry.path,
      snippet: line
    }
  end

  defp title(%{heading: nil, title: title}), do: title
  defp title(%{heading: heading, title: title}), do: title <> " › " <> heading

  # The whole search is the field, starts it, or is in it as typed, before words apart.
  defp closeness(field, phrase) do
    lower = String.downcase(field)

    cond do
      lower == phrase -> 0
      String.starts_with?(lower, phrase) -> 1
      word_matches(lower, phrase) != [] -> 2
      true -> 3
    end
  end

  defp all?(text, terms) do
    lower = String.downcase(text)
    Enum.all?(terms, &(word_matches(lower, &1) != []))
  end

  # Where `term` starts a word of `lower`, as byte offsets.
  defp word_matches(lower, term) do
    lower
    |> :binary.matches(term)
    |> Enum.filter(fn {at, _length} -> App.ViewData.Search.starts_word_at?(lower, at) end)
  end

  # The text around the first word typed, cut at spaces.
  defp snippet(text, terms) do
    lower = String.downcase(text)

    at =
      if byte_size(lower) == byte_size(text) do
        terms
        |> Enum.flat_map(&word_matches(lower, &1))
        |> Enum.map(&elem(&1, 0))
        |> Enum.min(fn -> 0 end)
      else
        0
      end

    from = if at < 40, do: 0, else: next_space(text, at - 40)
    rest = binary_part(text, from, byte_size(text) - from)
    if(from > 0, do: "…", else: "") <> start(rest)
  end

  defp next_space(text, at) do
    case :binary.match(text, " ", scope: {at, byte_size(text) - at}) do
      {space, 1} -> space + 1
      :nomatch -> at
    end
  end

  # The first #{@snippet} bytes or so, ending at a space.
  defp start(text) when byte_size(text) <= @snippet, do: text

  defp start(text) do
    case :binary.match(text, " ", scope: {@snippet, byte_size(text) - @snippet}) do
      {space, 1} -> binary_part(text, 0, space) <> " …"
      :nomatch -> text
    end
  end

  @doc """
  The recent picks the browser sent, as a Recent group: keys from `Web.Search.key/1`,
  newest first. Keys the index no longer has drop out.
  """
  def recent(keys, entries \\ index())

  def recent(keys, entries) when is_list(keys) do
    by_key =
      Map.new(entries, fn entry ->
        hit = shown(entry, if(entry.heading, do: start(entry.text), else: entry.about))
        {Web.Search.key(hit), hit}
      end)

    hits =
      keys
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.take(@recent)
      |> Enum.flat_map(&List.wrap(by_key[&1]))

    if hits == [], do: [], else: [%{kind: :recent, more?: false, hits: hits}]
  end

  def recent(_keys, _entries), do: []
end
