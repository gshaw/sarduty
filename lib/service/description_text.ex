defmodule Service.DescriptionText do
  @moduledoc """
  A D4H activity's description, which is HTML, as the plain text the activity form edits
  (#585). Text goes back as paragraphs, a blank line between each and `<br>` for a line
  break. A description with any other HTML, such as links or lists, is `:formatted`, so
  the form never flattens it.
  """

  @doc """
  `{:ok, text}` for a description of only paragraphs and line breaks, or of plain text,
  and `:formatted` for one with other HTML. `{:ok, nil}` for none.
  """
  def to_text(nil), do: {:ok, nil}

  def to_text(html) when is_binary(html) do
    paragraphs =
      html
      |> Floki.parse_fragment!()
      |> Enum.reduce_while([], fn node, paragraphs ->
        case paragraph(node) do
          {:ok, ""} -> {:cont, paragraphs}
          {:ok, text} -> {:cont, [text | paragraphs]}
          :formatted -> {:halt, :formatted}
        end
      end)

    case paragraphs do
      :formatted -> :formatted
      [] -> {:ok, nil}
      paragraphs -> {:ok, paragraphs |> Enum.reverse() |> Enum.join("\n\n")}
    end
  end

  # Plain text stays as it is, a description from before D4H's editor or from the API.
  defp paragraph(text) when is_binary(text), do: {:ok, String.trim(text)}

  defp paragraph({"p", [], children}) do
    if Enum.all?(children, &(is_binary(&1) or match?({"br", [], []}, &1))) do
      text =
        children
        |> Enum.map_join(fn
          {"br", [], []} -> "\n"
          text -> String.replace(text, ~r/\s+/u, " ")
        end)
        |> String.split("\n")
        |> Enum.map_join("\n", &String.trim/1)
        |> String.trim()

      {:ok, text}
    else
      :formatted
    end
  end

  defp paragraph(_node), do: :formatted

  @doc "The text as D4H's HTML: a `<p>` per paragraph, `<br>` per line break, escaped."
  def to_html(nil), do: nil

  def to_html(text) when is_binary(text) do
    html =
      text
      |> String.replace("\r\n", "\n")
      |> String.split(~r/\n\s*\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map_join(fn paragraph ->
        lines = paragraph |> String.split("\n") |> Enum.map_join("<br>", &escape(String.trim(&1)))
        "<p>#{lines}</p>"
      end)

    if html == "", do: nil, else: html
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
