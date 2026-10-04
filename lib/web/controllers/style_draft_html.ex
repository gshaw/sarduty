defmodule Web.StyleDraftHTML do
  use Web, :html

  alias Web.StyleGuide.SampleData

  embed_templates "style_draft_html/*"

  # The Writing page shows docs/writing.md, so agents and the guide read the same rules.
  @writing_path Path.expand("../../../docs/writing.md", __DIR__)
  @external_resource @writing_path
  @writing_html @writing_path
                |> File.read!()
                |> MDEx.to_html!(extension: [table: true, tasklist: true, header_id_prefix: ""])

  def writing_html, do: Phoenix.HTML.raw(@writing_html)

  # cspell:ignore Murrin

  # The guide's pages, in sidebar order: {group, [{page, title}]}. The page is also the
  # template name and the last path segment.
  def pages do
    [
      {"Start", [{:index, "Overview"}]},
      {"Foundations",
       [
         {:colors, "Colors"},
         {:typography, "Typography"},
         {:writing, "Writing"},
         {:layout, "Layout"}
       ]},
      {"Components",
       [
         {:components, "Buttons and tags"},
         {:navigation, "Navigation"},
         {:feedback, "Messages"},
         {:tables, "Tables"},
         {:forms, "Forms"}
       ]}
    ]
  end

  def page_path(:index), do: "/styles/draft"
  def page_path(page), do: "/styles/draft/#{page}"

  def type_scale do
    [
      {"2xl", 32, 40, "Page title (h1), big numbers"},
      {"xl", 24, 32, "Section heading (h2)"},
      {"lg", 19, 28, "Subheading (h3), lead text, legends"},
      {"md", 16, 24, "Body, labels, inputs, buttons"},
      {"sm", 14, 20, "Tables, hints, breadcrumbs, small buttons"},
      {"xs", 12, 16, "Tags, column group labels, captions"}
    ]
  end

  def spacing do
    [
      {1, 4, "Tag padding, label to input"},
      {2, 8, "Gaps between buttons in a row, hint to input"},
      {3, 12, "Table cell sides, card padding"},
      {4, 16, "Paragraph spacing, panel padding"},
      {5, 24, "Between form fields, page gutter"},
      {6, 32, "Between page header and content"},
      {7, 48, "Above a section heading"},
      {8, 64, "Bottom of the page"}
    ]
  end

  # The palette, as {token, light, dark, use}. The CSS is generated from this list, so the
  # swatches on the overview can't drift from what the pages use.
  def palette do
    [
      {"Surfaces",
       [
         {"bg", "#ffffff", "#0d1117", "Page background"},
         {"surface-alt", "#f3f2f1", "#161c24", "Table headers, panels, sunken areas"},
         {"row-alt", "#f8f8f7", "#121821", "Zebra rows"},
         {"row-hover", "#eaf2fa", "#1b2633", "Row under the pointer"},
         {"border", "#b1b4b6", "#3b4654", "Inputs and table rules"},
         {"border-subtle", "#dedfe0", "#252e39", "Row dividers"}
       ]},
      {"Text",
       [
         {"text", "#0b0c0c", "#e6e9ec", "Body text"},
         {"text-muted", "#505a5f", "#9aa6b2", "Hints, captions, secondary text"},
         {"link", "#1d70b8", "#7ab8f5", "Links"},
         {"link-hover", "#003078", "#b3d6fb", "Links under the pointer"}
       ]},
      {"Actions and status",
       [
         {"primary", "#1d4f91", "#3b7dd8", "Main buttons, current tab"},
         {"primary-hover", "#163d70", "#5592e0", "Main button under the pointer"},
         {"success", "#00703c", "#2ea56a", "Save, add, done"},
         {"danger", "#c2301a", "#e5533d", "Delete, remove, errors"},
         {"warning", "#f47738", "#f5a05a", "Warnings (fill, with dark text)"},
         {"info", "#1d70b8", "#4f9be6", "Notices"},
         {"focus", "#ffdd00", "#ffdd00", "Keyboard focus, both modes"}
       ]},
      {"Brand and D4H",
       [
         {"nav", "#13243a", "#0a111b", "Top bar"},
         {"accent", "#ffb81c", "#ffb81c", "Logo, top bar rule"},
         {"incident", "#2453a6", "#4d7fd6", "D4H incident"},
         {"exercise", "#b4500b", "#e07a33", "D4H exercise"},
         {"event", "#5b3ea6", "#8f72dd", "D4H event"}
       ]}
    ]
  end

  def palette_css do
    for {_group, tokens} <- palette(), {name, light, dark, _use} <- tokens, into: "" do
      "  --#{name}: light-dark(#{light}, #{dark});\n"
    end
  end

  defdelegate letters(), to: SampleData
  defdelegate recommendations(), to: SampleData
  defdelegate clauses(), to: SampleData

  def rule_preview do
    [
      {"Avery Chen", "Holds OFA Level 1 and GSAR Member, which meets both clauses of the rule.",
       "Added to D4H 2024-03-02", nil},
      {"Casey Dhillon", "Wilderness First Aid expires 2025-11-12.",
       "Renewal course booked for 2025-11-01", 12},
      {"Devon Okafor", "No First Aid qualification.", "Last held OFA Level 1, expired 2024-06-30",
       nil}
    ]
  end

  def activities do
    [
      {"2025-09-28", :incident, "Missing hiker, Stawamus Chief", 14, "62h 15m"},
      {"2025-09-24", :exercise, "Rope rescue, Murrin Park", 11, "33h 00m"},
      {"2025-09-21", :event, "Squamish Days first aid booth", 6, "24h 00m"},
      {"2025-09-17", :incident, "Overdue kayaker, Howe Sound", 9, "18h 45m"},
      {"2025-09-14", :exercise, "Night navigation", 16, "48h 00m"},
      {"2025-09-10", :event, "Team meeting", 22, "33h 00m"},
      {"2025-09-06", :incident, "Injured biker, Diamond Head", 12, "29h 30m"},
      {"2025-09-03", :exercise, "Swiftwater refresher", 8, "32h 00m"},
      {"2025-08-30", :incident, "Lost child, Alice Lake", 19, "41h 15m"},
      {"2025-08-27", :exercise, "Helicopter longline", 7, "21h 00m"}
    ]
  end
end
