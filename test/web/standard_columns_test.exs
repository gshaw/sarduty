defmodule Web.StandardColumnsTest do
  use ExUnit.Case, async: true

  # A column that recurs reads the same on every table (#740): Web.Components.Columns has
  # a cell for each, and /styles/table shows them. Each rule below lists its exceptions,
  # each with its reason.

  # A record column: its label, its cell, and the link it owns. A table links to the
  # record only through the cell, and the cell sits under the label.
  @records [
    {"Member", "<.member_cell", ~r|/members/\#\{[^}]*\}(/[a-z]+)?["?]|},
    {"Activity", "<.activity_cell", ~r|/activities/\#\{[^}]*\}(/[a-z]+)?["?]|},
    {"Item", "<.item_cell", ~r|/equipment/\#\{[^}]*\}["?]|},
    {"Qualification", "<.qualification_cell", ~r|/qualifications/\#\{[^}]*\}["?]|},
    {"Group", "<.group_cell", ~r|/groups/\#\{[^}]*\}["?]|}
  ]

  # A value column: its label, its cell, whether it's right-aligned, and the formatters
  # only its cell calls.
  @values [
    {"Date", "<.date_cell", false, ~r/Format\.(date_short|month_day|day_in_year)\(/},
    {"Expires", "<.expires_cell", false, nil},
    {"Hours", "<.hours_cell", true, ~r/Format\.duration\(/},
    {"Last attended", "<.last_attended_cell", false, nil}
  ]

  @linked_by_hand %{
    {"lib/web/live/group_live.ex", "Change"} =>
      "Recent changes: the member's name is one word in a sentence"
  }

  @labelled_without_cell %{
    {"lib/web/live/milestone_collection_live.ex", "Activity"} =>
      "plain text: which activity tipped a total over a line is chance",
    {"lib/web/live/certificate_collection_live.ex", "Qualification"} =>
      "the certificate, named by the qualification it asks for, links its own page",
    {"lib/web/live/endorsement_form_live.ex", "Qualification"} =>
      "a qualification D4H deleted shows by its D4H id, with no page to link",
    {"lib/web/live/activity_mileage_live.ex", "Hours"} =>
      "Mapbox's driving time in tenths of an hour, for the mileage claim"
  }

  @formatted_by_hand %{
    {"lib/web/live/member_standing_live.ex", ""} =>
      "the Delete button's confirm names the check-in's day in a sentence"
  }

  # Where people pick an activity by when it runs.
  @times_allowed [
    "lib/web/components/activity_filter_table.ex",
    "lib/web/controllers/style_guide_html/pages/table.html.heex"
  ]

  @cell_labelled_otherwise %{
    {"lib/web/live/activity_send_update_live.ex", "{status_title(status)}"} =>
      "a table per reply, each headed by the reply",
    {"lib/web/live/activity_remove_members_live.ex", "{Reply.status_text(status, false)}"} =>
      "a table per reply, each headed by the reply",
    {"lib/web/controllers/style_guide_html/pages/table.html.heex", "Looks like"} =>
      "the style guide's list of the standard columns, one of each"
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

      %{path: path, label: label, attrs: attrs, body: body}
    end
  end

  defp uses?(col, cell), do: String.contains?(col.body, cell)

  defp check(found, allowed, message) do
    unlisted = found |> Enum.uniq() |> Enum.reject(&Map.has_key?(allowed, &1))
    assert unlisted == [], message <> ":\n" <> Enum.map_join(unlisted, "\n", &inspect/1)
  end

  defp check_stale(found, allowed) do
    stale = Map.keys(allowed) -- Enum.uniq(found)
    assert stale == [], "No longer in the code, so remove: #{inspect(stale)}"
  end

  test "the parser finds the standard columns" do
    assert Enum.count(columns(), &uses?(&1, "<.member_cell")) >= 20
    assert Enum.count(columns(), &uses?(&1, "<.date_cell")) >= 15
  end

  test "a table links to a record only through its cell" do
    found =
      for col <- columns(),
          {_label, cell, link} <- @records,
          col.body =~ link,
          not uses?(col, cell),
          do: {col.path, col.label}

    check(found, @linked_by_hand, "Use the column's cell, or add the reason here")
    check_stale(found, @linked_by_hand)
  end

  test "a standard column's label has its cell" do
    found =
      for col <- columns(),
          {label, cell} <- Enum.map(@records, &Tuple.delete_at(&1, 2)) ++ value_cells(),
          col.label == label,
          not uses?(col, cell),
          do: {col.path, col.label}

    check(found, @labelled_without_cell, "Use the column's cell, or add the reason here")
    check_stale(found, @labelled_without_cell)
  end

  test "a record cell sits under its column's label" do
    found =
      for col <- columns(),
          {label, cell, _link} <- @records,
          uses?(col, cell),
          col.label != label,
          do: {col.path, col.label}

    check(found, @cell_labelled_otherwise, "Label the column, or add the reason here")
    check_stale(found, @cell_labelled_otherwise)
  end

  test "a value column has its alignment, and its formatter only through its cell" do
    misaligned =
      for col <- columns(),
          {label, _cell, right?, _formatter} <- @values,
          col.label == label,
          String.contains?(col.attrs, ~s(align="right")) != right?,
          do: "#{col.path}: #{label} #{if right?, do: "is", else: "isn't"} right-aligned"

    by_hand =
      for col <- columns(),
          {_label, cell, _right?, formatter} <- @values,
          formatter,
          col.body =~ formatter,
          not uses?(col, cell),
          do: {col.path, col.label}

    assert misaligned == [], Enum.join(misaligned, "\n")
    check(by_hand, @formatted_by_hand, "Format it with the column's cell, or add the reason here")
    check_stale(by_hand, @formatted_by_hand)
  end

  test "only the Activities list shows an activity's times under its date" do
    found =
      for col <- columns(),
          col.body =~ ~r/<\.date_cell[^>]*\stimes\b/,
          do: col.path

    assert Enum.uniq(found) -- @times_allowed == []
  end

  defp value_cells, do: for({label, cell, _right?, _formatter} <- @values, do: {label, cell})
end
