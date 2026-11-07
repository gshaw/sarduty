defmodule Web.TableFitTest do
  use ExUnit.Case, async: true

  # Columns that stay put (/styles/table#fit): in a table that filters, one column takes
  # the rest and every other column fits its longest values or takes a set share, so a
  # tile, the search, or a page never moves a column.

  # Tables in components that a page with tiles, filters, or pages draws.
  @drawn_in_a_filtered_page [
    "lib/web/components/activity_table.ex",
    "lib/web/components/report_table.ex"
  ]

  # Tables still to fit, each with the part of the rollout that fits it. A part deletes
  # its lines here.
  @to_fit %{
    "lib/web/components/activity_table.ex" => "Members, Activities, and reports",
    "lib/web/components/report_table.ex" => "Members, Activities, and reports",
    "lib/web/live/member_collection_live.ex" => "Members, Activities, and reports",
    "lib/web/live/report_collection_live.ex" => "Members, Activities, and reports",
    "lib/web/live/equipment_collection_live.ex" => "Equipment, qualifications, and certificates",
    "lib/web/live/qualification_collection_live.ex" =>
      "Equipment, qualifications, and certificates",
    "lib/web/live/qualification_live.ex" => "Equipment, qualifications, and certificates",
    "lib/web/live/certificate_collection_live.ex" =>
      "Equipment, qualifications, and certificates",
    "lib/web/live/milestone_collection_live.ex" => "Milestones, letters, hours, and the rest",
    "lib/web/live/tax_credit_letter_collection_live.ex" =>
      "Milestones, letters, hours, and the rest",
    "lib/web/components/attendance_filter_table.ex" => "Milestones, letters, hours, and the rest",
    "lib/web/live/chore_collection_live.ex" => "Milestones, letters, hours, and the rest",
    "lib/web/live/whiteboard_live.ex" => "Milestones, letters, hours, and the rest",
    "lib/web/live/group_collection_live.ex" => "Milestones, letters, hours, and the rest",
    "lib/web/live/admin_dashboard_live.ex" => "Milestones, letters, hours, and the rest",
    "lib/web/live/org/team_collection_live.ex" => "Milestones, letters, hours, and the rest",
    "lib/web/live/admin/event_collection_live.ex" => "Milestones, letters, hours, and the rest"
  }

  # A column besides the rest with neither a fit nor a share, by file and label.
  @unfitted %{
    {"lib/web/live/report_form_live.ex", "Draws"} =>
      "the editor's list of clauses, which its report's filters never change",
    {"lib/web/live/report_form_live.ex", "Takes"} =>
      "the editor's list of charts, which its report's filters never change"
  }

  defp tables(path) do
    for [attrs, body] <-
          Regex.scan(~r/<\.table\b(.*?)>(.*?)<\/\.table>/s, File.read!(path),
            capture: :all_but_first
          ) do
      cols =
        for [col] <- Regex.scan(~r/<:col\b(.*?)>/s, body, capture: :all_but_first), do: col(col)

      id = Regex.run(~r/\bid=(\S+)/, attrs, capture: :all_but_first)
      %{id: id && hd(id), cols: cols}
    end
  end

  defp col(attrs) do
    %{
      label: label(attrs),
      fit?: attrs =~ ~r/\bfit=\{/,
      share?: attrs =~ ~r/\bw-\d+\/\d+\b/,
      nowrap?: attrs =~ ~r/\b(w-px|whitespace-nowrap)\b/,
      check_or_button?: attrs =~ ~r/\bselect_all\b/ or label(attrs) == "",
      for?: attrs =~ ~r/:for=/
    }
  end

  defp label(col) do
    case Regex.run(~r/\blabel=(?:"([^"]*)"|\{(.*?)\}\s)/s, col, capture: :all_but_first) do
      [text] -> text
      ["", expr] -> "{#{expr}}"
      nil -> ""
    end
  end

  defp files, do: Path.wildcard("lib/web/**/*.{ex,heex}")

  defp filtered?(path) do
    path in @drawn_in_a_filtered_page or
      File.read!(path) =~ ~r/<\.(stat_switch|filter_bar|report_page|pagination)\b/
  end

  # The columns with neither a fit nor a share. A column drawn with :for is many columns.
  defp unfitted(path, table) do
    table.cols
    |> Enum.reject(
      &(&1.fit? or &1.share? or &1.check_or_button? or Map.has_key?(@unfitted, {path, &1.label}))
    )
    |> Enum.flat_map(&if(&1.for?, do: [&1, &1], else: [&1]))
  end

  test "in a table that filters, one column takes the rest and the others fit" do
    found =
      for path <- files(),
          filtered?(path),
          not Map.has_key?(@to_fit, path),
          table <- tables(path),
          unfitted = unfitted(path, table),
          length(unfitted) > 1,
          do:
            "#{path} #{table.id}: #{unfitted |> Enum.uniq() |> Enum.map_join(", ", &inspect(&1.label))}"

    assert found == [],
           "One column takes the rest; fit the others or give them a share (/styles/table#fit):\n" <>
             Enum.join(found, "\n")
  end

  test "a fit takes the place of w-px and whitespace-nowrap" do
    found =
      for path <- files(),
          table <- tables(path),
          col <- table.cols,
          col.fit? and col.nowrap?,
          do: "#{path}: #{col.label}"

    assert found == [],
           "Drop w-px and whitespace-nowrap where a column fits:\n" <> Enum.join(found, "\n")
  end

  test "every table still to fit filters, and its file exists" do
    stale = for {path, _part} <- @to_fit, not (File.exists?(path) and filtered?(path)), do: path
    assert stale == [], "Remove from @to_fit: #{inspect(stale)}"

    stale = for {{path, _label}, _reason} <- @unfitted, not File.exists?(path), do: path
    assert stale == [], "Remove from @unfitted: #{inspect(stale)}"
  end

  test "every table still to fit doesn't fit yet" do
    done =
      for {path, _part} <- @to_fit,
          File.exists?(path),
          path |> tables() |> Enum.all?(&(length(unfitted(path, &1)) <= 1)),
          do: path

    assert done == [], "These fit now, so remove them from @to_fit: #{inspect(done)}"
  end
end
