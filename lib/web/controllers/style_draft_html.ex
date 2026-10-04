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
         {:colors, "Colours"},
         {:typography, "Typography"},
         {:writing, "Writing"},
         {:icons, "Icons"},
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

  # The icon set is Heroicons, as in the app. Only these render, so adding one means adding
  # it here with its use. Sizes: 16 and 20 are solid, 24 is outline.
  @icons [
    {"chevron-left", "Back link, previous page"},
    {"chevron-right", "Breadcrumb separator, next page"},
    {"chevron-down", "Details and menus that open"},
    {"arrow-top-right-on-square", "A link that leaves SAR Duty, such as Open in D4H"},
    {"arrow-path", "Refresh from D4H"},
    {"arrow-down-tray", "Download a file, such as a letter PDF"},
    {"plus", "Add a clause or a qualification"},
    {"x-mark", "Close a toast, remove a chip"},
    {"check-circle", "Success banners and toasts"},
    {"information-circle", "Info banners and toasts"},
    {"exclamation-triangle", "Warning banners and warning text"},
    {"exclamation-circle", "Error banners, toasts, and error summaries"}
  ]

  @icon_markup (for {name, _use} <- @icons,
                    {size, dir} <- [{16, "16/solid"}, {20, "20/solid"}, {24, "24/outline"}],
                    into: %{} do
                  svg =
                    "../../../deps/heroicons/optimized/#{dir}/#{name}.svg"
                    |> Path.expand(__DIR__)
                    |> File.read!()
                    |> String.replace("<svg ", ~s(<svg class="icon icon-#{size}" ), global: false)
                    |> String.replace(~r/\s+/, " ")

                  {{name, size}, svg}
                end)

  def icons, do: @icons

  attr :name, :string, required: true
  attr :size, :integer, default: 20, values: [16, 20, 24]

  def svg_icon(assigns) do
    svg = @icon_markup |> Map.fetch!({assigns.name, assigns.size}) |> Phoenix.HTML.raw()
    assigns = assign(assigns, :svg, svg)

    ~H"{@svg}"
  end

  def button_kinds do
    [
      {nil, "Primary"},
      {"secondary", "Secondary"},
      {"success", "Success"},
      {"danger", "Danger"},
      {"link", "Link"}
    ]
  end

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
         {"primary", "#1d4f91", "#2f6fc4", "Main buttons, current tab, page number"},
         {"primary-hover", "#163d70", "#2563b0", "Main button under the pointer or pressed"},
         {"success", "#00703c", "#1f7f4c", "Fills: save and add buttons, success banner"},
         {"success-text", "#00703c", "#4cc38a", "Green text: Add, tinted success tags"},
         {"danger", "#c2301a", "#c93a24", "Fills: delete buttons, danger tags and banners"},
         {"danger-text", "#c2301a", "#ff8a75", "Red text: Remove, error messages"},
         {"warning", "#ffb81c", "#ffb81c", "Amber fill with dark text: act soon"},
         {"info", "#1d70b8", "#2a66b8", "Fills: notices, info banner"},
         {"focus", "#ffdd00", "#ffdd00", "Keyboard focus, both modes"}
       ]},
      {"Brand and D4H",
       [
         {"nav", "#13243a", "#0a111b", "Top bar"},
         {"accent", "#ffb81c", "#ffb81c", "Logo, top bar rule"},
         {"incident", "#2453a6", "#3366c0", "D4H incident"},
         {"exercise", "#b4500b", "#b8560f", "D4H exercise"},
         {"event", "#5b3ea6", "#6a4cc0", "D4H event"}
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
       "Added to D4H Mar 2, 2024", nil},
      {"Casey Dhillon", "Wilderness First Aid expires Nov 12, 2025.",
       "Renewal course booked for Nov 1, 2025", 12},
      {"Devon Okafor", "No First Aid qualification.",
       "Last held OFA Level 1, expired Jun 30, 2024", nil}
    ]
  end

  def activities do
    [
      {"Sep 28, 2025", :incident, "Missing hiker, Stawamus Chief", 14, "62h 15m"},
      {"Sep 24, 2025", :exercise, "Rope rescue, Murrin Park", 11, "33h 00m"},
      {"Sep 21, 2025", :event, "Squamish Days first aid booth", 6, "24h 00m"},
      {"Sep 17, 2025", :incident, "Overdue kayaker, Howe Sound", 9, "18h 45m"},
      {"Sep 14, 2025", :exercise, "Night navigation", 16, "48h 00m"},
      {"Sep 10, 2025", :event, "Team meeting", 22, "33h 00m"},
      {"Sep 6, 2025", :incident, "Injured biker, Diamond Head", 12, "29h 30m"},
      {"Sep 3, 2025", :exercise, "Swiftwater refresher", 8, "32h 00m"},
      {"Aug 30, 2025", :incident, "Lost child, Alice Lake", 19, "41h 15m"},
      {"Aug 27, 2025", :exercise, "Helicopter longline", 7, "21h 00m"}
    ]
  end
end
