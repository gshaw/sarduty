defmodule App.Adapter.D4H.WhiteboardNote do
  alias App.Adapter.D4H.Parse

  defstruct d4h_whiteboard_note_id: nil,
            text: nil,
            url: nil,
            important: false,
            owner_kind: :team,
            archived_at: nil,
            created_at: nil

  # A note on the team's whiteboard (#515). D4H's spec says the text may be HTML. No
  # note held any on 2026-10-20, and SAR Duty shows plain text, so tags are dropped here.
  def build(record) do
    owner = if is_map(record["owner"]), do: record["owner"], else: %{}

    %__MODULE__{
      d4h_whiteboard_note_id: record["id"],
      text: plain_text(record["text"]),
      url: blank_to_nil(record["url"]),
      important: record["important"] == true,
      owner_kind: if(owner["resourceType"] == "Organisation", do: :organization, else: :team),
      archived_at: Parse.optional_datetime(record["archivedAt"]),
      created_at: Parse.optional_datetime(record["createdAt"])
    }
  end

  # cspell:ignore nbsp -- the HTML entity for a non-breaking space
  @entities [{"&nbsp;", " "}, {"&lt;", "<"}, {"&gt;", ">"}, {"&quot;", "\""}, {"&#39;", "'"}]

  @doc "The text without HTML tags, its common entities read, and its spaces squeezed."
  def plain_text(nil), do: ""

  def plain_text(text) do
    text = Regex.replace(~r/<br\s*\/?>|<\/p>/i, text, " ")
    text = Regex.replace(~r/<[^>]*>/, text, "")

    text =
      Enum.reduce(@entities, text, fn {entity, char}, text ->
        String.replace(text, entity, char)
      end)

    text
    |> String.replace("&amp;", "&")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp blank_to_nil(url) when url in [nil, ""], do: nil
  defp blank_to_nil(url), do: url
end
