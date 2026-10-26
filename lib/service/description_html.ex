defmodule Service.DescriptionHTML do
  @moduledoc """
  An activity's description as the activity form edits it: HTML with only paragraphs,
  line breaks, bold, italics, links, and lists, the way chore events are written (#598).
  Pasted colours, fonts, and sizes are dropped, so every description reads alike. A
  description with things the editor can't hold, such as a table, an image, or a
  heading, is not `editable?/1`, so the form never flattens it.
  """

  # Tags the editor holds, or drops without losing anything people meant: a span or a
  # font only carries a colour or a size. b and i become strong and em.
  @editable ~w(p div br span font u strong b em i a ul ol li)

  @doc "Whether the form can edit `html` without losing more than its styling."
  def editable?(nil), do: true

  def editable?(html) when is_binary(html),
    do: html |> parse() |> Enum.all?(&editable_node?/1)

  defp editable_node?({tag, _attrs, children}) when tag in @editable,
    do: Enum.all?(children, &editable_node?/1)

  defp editable_node?({:comment, _}), do: true
  defp editable_node?(text) when is_binary(text), do: true
  defp editable_node?(_node), do: false

  @doc """
  `html` with only the tags the editor makes, or nil when it says nothing. Plain text, from
  before D4H's editor or from a Records team, becomes paragraphs: a blank line between
  each, and a line break where it had one.
  """
  def clean(nil), do: nil

  def clean(html) when is_binary(html) do
    nodes = parse(html)

    blocks =
      if Enum.all?(nodes, &is_binary/1),
        do: text_blocks(Enum.join(nodes)),
        else: blocks(nodes)

    case Enum.map_join(blocks, &to_html/1) do
      "" -> nil
      html -> html
    end
  end

  # Floki drops text that is only spaces, such as the one in "<b>Date:</b> <i>soon</i>",
  # but keeps a character reference.
  defp parse(html), do: html |> String.replace(~r/>\s+</u, ">&#32;<") |> Floki.parse_fragment!()

  defp text_blocks(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.split(~r/\n\s*\n/)
    |> Enum.flat_map(fn paragraph ->
      paragraph
      |> String.split("\n")
      |> Enum.intersperse({"br", [], []})
      |> inline()
      |> paragraph()
    end)
  end

  # Block level: p and div hold paragraphs, and lists stay lists. Anything else between
  # them is a run of inline nodes that becomes paragraphs.
  defp blocks(nodes) do
    nodes
    |> Enum.chunk_by(&block?/1)
    |> Enum.flat_map(fn [node | _] = run ->
      if block?(node), do: Enum.flat_map(run, &block/1), else: paragraphs(run)
    end)
  end

  defp block?({tag, _attrs, _children}), do: tag in ~w(p div ul ol)
  defp block?(_node), do: false

  defp block({tag, _attrs, children}) when tag in ~w(p div), do: blocks(children)
  defp block({tag, _attrs, children}), do: list(tag, children)

  # Two line breaks in a row, as the editor writes a blank line, start a new paragraph.
  defp paragraphs(nodes) do
    nodes
    |> inline()
    |> drop_space_after_breaks()
    |> Enum.chunk_while(
      [],
      fn
        {"br", [], []}, [{"br", [], []} | rest] -> {:cont, Enum.reverse(rest), []}
        node, acc -> {:cont, [node | acc]}
      end,
      &{:cont, Enum.reverse(&1), []}
    )
    |> Enum.flat_map(&paragraph/1)
  end

  defp drop_space_after_breaks([{"br", [], []}, " " | rest]),
    do: drop_space_after_breaks([{"br", [], []} | rest])

  defp drop_space_after_breaks([node | rest]), do: [node | drop_space_after_breaks(rest)]
  defp drop_space_after_breaks([]), do: []

  defp paragraph(nodes) do
    case trim(nodes) do
      [] -> []
      nodes -> [{"p", [], nodes}]
    end
  end

  defp list(tag, children) do
    items =
      Enum.flat_map(children, fn
        {"li", _attrs, kids} -> item(kids)
        {tag, _attrs, kids} when tag in ~w(ul ol) -> list(tag, kids)
        node -> item([node])
      end)

    if items == [], do: [], else: [{tag, [], items}]
  end

  # A list item's text, then any list nested in it.
  defp item(nodes) do
    {lists, text} = Enum.split_with(nodes, &match?({tag, _, _} when tag in ~w(ul ol), &1))
    text = text |> Enum.flat_map(&item_text/1) |> inline() |> trim() |> single_breaks()
    lists = Enum.flat_map(lists, fn {tag, _attrs, kids} -> list(tag, kids) end)

    if text == [] and lists == [], do: [], else: [{"li", [], text ++ lists}]
  end

  # A paragraph in a list item is a line of it.
  defp item_text({tag, _attrs, kids}) when tag in ~w(p div), do: [{"br", [], []} | kids]
  defp item_text(node), do: [node]

  defp single_breaks([{"br", [], []}, {"br", [], []} | rest]),
    do: single_breaks([{"br", [], []} | rest])

  defp single_breaks([node | rest]), do: [node | single_breaks(rest)]
  defp single_breaks([]), do: []

  # Text next to text, as unwrapping a span leaves it, is one text, so cleaning twice gives
  # the same HTML.
  defp inline(nodes) do
    nodes
    |> Enum.flat_map(&inline_node/1)
    |> Enum.chunk_by(&is_binary/1)
    |> Enum.flat_map(fn
      [text | _] = texts when is_binary(text) ->
        [texts |> Enum.join() |> String.replace(~r/[\s\x{00A0}]+/u, " ")]

      nodes ->
        nodes
    end)
  end

  defp inline_node(text) when is_binary(text), do: [text]

  defp inline_node({"br", _attrs, _children}), do: [{"br", [], []}]
  defp inline_node({tag, _attrs, kids}) when tag in ~w(strong b), do: wrap("strong", [], kids)
  defp inline_node({tag, _attrs, kids}) when tag in ~w(em i), do: wrap("em", [], kids)

  defp inline_node({"a", attrs, kids}) do
    case attrs |> List.keyfind("href", 0) |> safe_href() do
      nil -> inline(kids)
      href -> wrap("a", [{"href", href}], kids)
    end
  end

  defp inline_node({tag, _attrs, kids}) when is_binary(tag), do: inline(kids)
  defp inline_node(_comment), do: []

  # Line breaks at either end go outside, as Trix ends a paragraph inside its last link
  # ("<a>Map<br></a>"), so a paragraph's trim finds them.
  defp wrap(tag, attrs, kids) do
    {before, nodes} = kids |> inline() |> Enum.split_while(&(&1 == {"br", [], []}))
    {rest, nodes} = nodes |> Enum.reverse() |> Enum.split_while(&(&1 == {"br", [], []}))
    nodes = Enum.reverse(nodes)

    cond do
      nodes == [] -> before ++ rest
      Enum.all?(nodes, &(&1 == " ")) -> before ++ nodes ++ rest
      true -> Enum.concat([before, [nest({tag, attrs, nodes})], rest])
    end
  end

  # Tags around the same text go link, bold, italic from the outside in, as Trix writes
  # them, so "<em><strong>" and "<strong><em>" are the same description.
  @order %{"a" => 0, "strong" => 1, "em" => 2}

  defp nest({tag, attrs, [{inner, inner_attrs, kids}]} = node) when is_map_key(@order, inner) do
    if @order[inner] < @order[tag],
      do: {inner, inner_attrs, [nest({tag, attrs, kids})]},
      else: node
  end

  defp nest(node), do: node

  defp safe_href({"href", href}) do
    href = String.trim(href)
    if href =~ ~r/^(https?:|mailto:|tel:)/i, do: href
  end

  defp safe_href(nil), do: nil

  # No spaces or line breaks at either end, or next to a line break.
  defp trim(nodes) do
    nodes
    |> drop_edge(&String.trim_leading/1)
    |> Enum.reverse()
    |> drop_edge(&String.trim_trailing/1)
    |> Enum.reverse()
    |> trim_breaks()
  end

  defp drop_edge([{"br", [], []} | rest], fun), do: drop_edge(rest, fun)

  defp drop_edge([text | rest], fun) when is_binary(text) do
    case fun.(text) do
      "" -> drop_edge(rest, fun)
      text -> [text | rest]
    end
  end

  defp drop_edge(nodes, _fun), do: nodes

  defp trim_breaks([text, {"br", [], []} | rest]) when is_binary(text),
    do: [String.trim_trailing(text) | trim_breaks([{"br", [], []} | rest])]

  defp trim_breaks([{"br", [], []}, text | rest]) when is_binary(text),
    do: [{"br", [], []} | trim_breaks([String.trim_leading(text) | rest])]

  defp trim_breaks([node | rest]), do: [node | trim_breaks(rest)]
  defp trim_breaks([]), do: []

  defp to_html(text) when is_binary(text),
    do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp to_html({"br", [], []}), do: "<br>"

  defp to_html({tag, attrs, children}) do
    attrs = Enum.map_join(attrs, fn {name, value} -> ~s( #{name}="#{to_html(value)}") end)
    "<#{tag}#{attrs}>#{Enum.map_join(children, &to_html/1)}</#{tag}>"
  end
end
