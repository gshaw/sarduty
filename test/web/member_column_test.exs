defmodule Web.MemberColumnTest do
  use ExUnit.Case, async: true

  # Every table that lists members shows them the same way (#740): a column labelled
  # Member, with <.member_cell>, which links the name and adds the standing badge.
  # /styles/table, Standard columns.

  # A column that links to a member's page, or one of its tabs, some other way needs its
  # reason here.
  @linked_by_hand %{
    {"lib/web/live/group_live.ex", "Change"} =>
      "Recent changes: the member's name is one word in a sentence"
  }

  # A Member column labelled something else needs its reason here.
  @labelled_otherwise %{
    {"lib/web/live/activity_send_update_live.ex", "{status_title(status)}"} =>
      "a table per reply, each headed by the reply"
  }

  defp columns do
    for path <- Path.wildcard("lib/web/**/*.{ex,heex}"),
        [_, attrs, body] <-
          Regex.scan(~r/<:col\b((?:[^>{]|\{[^}]*\})*)>(.*?)<\/:col>/s, File.read!(path)) do
      label =
        case Regex.run(~r/\blabel=(?:"([^"]*)"|(\{[^}]*\}))/, attrs) do
          [_, text] -> text
          [_, "", expression] -> expression
          nil -> nil
        end

      %{path: path, label: label, body: body}
    end
  end

  test "the parser finds the member tables" do
    assert Enum.count(columns(), &String.contains?(&1.body, "<.member_cell")) >= 20
  end

  test "a table links to a member only through <.member_cell>" do
    found =
      for col <- columns(),
          col.body =~ ~r|/members/\#\{[^}]*\}(/[a-z]+)?["?]|,
          not String.contains?(col.body, "<.member_cell"),
          do: {col.path, col.label}

    unlisted = found |> Enum.uniq() |> Enum.reject(&Map.has_key?(@linked_by_hand, &1))

    assert unlisted == [],
           "Use <.member_cell> in a Member column, or add the reason here:\n" <>
             Enum.map_join(unlisted, "\n", fn {path, label} -> "#{path}: #{label}" end)

    stale = Map.keys(@linked_by_hand) -- found
    assert stale == [], "No longer in the code, so remove: #{inspect(stale)}"
  end

  test "a Member column uses <.member_cell>, and <.member_cell> is in a Member column" do
    plain =
      for col <- columns(),
          col.label == "Member",
          not String.contains?(col.body, "<.member_cell"),
          do: "#{col.path}: a Member column without <.member_cell>"

    found =
      for col <- columns(),
          String.contains?(col.body, "<.member_cell"),
          col.label != "Member",
          do: {col.path, col.label}

    unlisted =
      found
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(@labelled_otherwise, &1))
      |> Enum.map(fn {path, label} -> "#{path}: <.member_cell> under #{inspect(label)}" end)

    assert plain ++ unlisted == [], Enum.join(plain ++ unlisted, "\n")

    stale = Map.keys(@labelled_otherwise) -- found
    assert stale == [], "No longer in the code, so remove: #{inspect(stale)}"
  end
end
