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

  # cspell:ignore Murrin HETS

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

  # The palette comes from assets/css/tokens.css, the file the app uses, as
  # [{group, [{token, light, dark, use}]}]. The guide includes the same file, so its swatches
  # are the app's colours.
  @tokens_path Path.expand("../../../assets/css/tokens.css", __DIR__)
  @external_resource @tokens_path
  @tokens_css File.read!(@tokens_path)

  @palette @tokens_css
           |> String.split("\n")
           |> Enum.reduce([], fn line, groups ->
             group = Regex.run(~r{/\* group: (.+?) \*/}, line)
             token = Regex.run(~r{--([a-z-]+): light-dark\((#\w+), (#\w+)\); /\* (.+?) \*/}, line)

             case {group, token, groups} do
               {[_, name], _, _} ->
                 [{name, []} | groups]

               {nil, [_, n, l, d, use], [{g, tokens} | rest]} ->
                 [{g, [{n, l, d, use} | tokens]} | rest]

               _ ->
                 groups
             end
           end)
           |> Enum.map(fn {group, tokens} -> {group, Enum.reverse(tokens)} end)
           |> Enum.reverse()

  def palette, do: @palette
  def tokens_css, do: Phoenix.HTML.raw(@tokens_css)

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
      {"Sep 28, 2025", :incident, "Missing hiker, Stawamus Chief", 14, "62h 15m",
       ["Primary hours"], "25-0412", false},
      {"Sep 24, 2025", :exercise, "Rope rescue, Murrin Park", 11, "33h 00m",
       ["Secondary hours", "Rope"], nil, false},
      {"Sep 21, 2025", :event, "Squamish Days first aid booth", 6, "24h 00m", ["Secondary hours"],
       nil, false},
      {"Sep 17, 2025", :incident, "Overdue kayaker, Howe Sound", 9, "18h 45m",
       ["Primary hours", "Marine"], "25-0398", false},
      {"Sep 14, 2025", :exercise, "Night navigation", 16, "48h 00m", ["Secondary hours"], nil,
       false},
      {"Sep 10, 2025", :event, "Team meeting", 22, "33h 00m", [], nil, true},
      {"Sep 6, 2025", :incident, "Injured biker, Diamond Head", 12, "29h 30m", ["Primary hours"],
       "25-0371", false},
      {"Sep 3, 2025", :exercise, "Swiftwater refresher", 8, "32h 00m",
       ["Secondary hours", "Swiftwater"], nil, true},
      {"Aug 30, 2025", :incident, "Lost child, Alice Lake", 19, "41h 15m", ["Primary hours"],
       "25-0355", false},
      {"Aug 27, 2025", :exercise, "Helicopter longline", 7, "21h 00m",
       ["Secondary hours", "HETS"], nil, false}
    ]
    |> Enum.map(fn {date, kind, title, count, hours, tags, number, draft} ->
      %{
        date: date,
        kind: kind,
        title: title,
        count: count,
        hours: hours,
        hours_type: hours_type(tags),
        tags: tags -- ["Primary hours", "Secondary hours"],
        number: number,
        draft: draft
      }
    end)
  end

  # D4H's hours tags become a word in the Hours cell; the rest stay tags.
  defp hours_type(tags) do
    cond do
      "Primary hours" in tags -> "Primary"
      "Secondary hours" in tags -> "Secondary"
      true -> nil
    end
  end
end
