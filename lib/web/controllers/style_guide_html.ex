defmodule Web.StyleGuideHTML do
  use Web, :html

  import Web.Components.ActivityMap, only: [activity_map: 1]
  import Web.Components.ActivityFilterTable, only: [activity_table: 1]
  import Web.Components.Breadcrumbs
  import Web.Components.Chart
  import Web.Components.D4H
  import Web.Components.Pagination
  import Web.Components.Table

  alias Web.StyleGuideHTML.SampleData

  embed_templates "style_guide_html/*"

  # The Writing page shows docs/writing.md, so agents and the guide read the same rules.
  @writing_path Path.expand("../../../docs/writing.md", __DIR__)
  @external_resource @writing_path
  @writing_html @writing_path
                |> File.read!()
                |> MDEx.to_html!(extension: [table: true, tasklist: true, header_id_prefix: ""])

  def writing_html, do: Phoenix.HTML.raw(@writing_html)

  # cspell:ignore HETS

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
         {:logo, "Logo"},
         {:icons, "Icons"},
         {:layout, "Layout"}
       ]},
      {"Components",
       [
         {:components, "Buttons and tags"},
         {:navigation, "Navigation"},
         {:feedback, "Messages"},
         {:tables, "Tables"},
         {:forms, "Forms"},
         {:charts, "Charts and maps"}
       ]}
    ]
  end

  def page_path(:index), do: "/styles"
  def page_path(page), do: "/styles/#{page}"

  # The logo files that uv run assets/brand/draw_logo.py writes, and where each goes.
  def logo_files do
    [
      {"sarduty-logo.svg", "Stacked, with rounded corners. Pages that show the logo."},
      {"sarduty-logo-square.svg",
       "Stacked, square corners. The source for phones and Google, which round it themselves."},
      {"sarduty-logo-square.png",
       "1024 pixels. Google's business profile, which crops it to a circle."},
      {"apple-touch-icon.png", "180 pixels. The phone home screen."},
      {"sarduty-logo-96.png", "The login email, shown at 48 pixels."},
      {"sarduty-favicon.svg", "SD. The browser tab."},
      {"priv/static/favicon.ico",
       "SD at 16, 32, and 48 pixels, for browsers that ask for it by name."},
      {"sarduty-logo-wide.svg", "Wide, for where text can't go."},
      {"sarduty-logo-wide.png",
       "Wide, 828 by 256 pixels, for email and sites that won't take SVG."},
      {"priv/apple/sarduty_logo.png", "Apple Wallet's logo and icon for a team with no logo."}
    ]
  end

  # The icon set: Heroicons through <.icon>, as in the app. Each name is written out in full
  # so Tailwind's heroicons plugin finds it and builds its class.
  def icons do
    [
      {"chevron-left", "hero-chevron-left-micro", "hero-chevron-left-mini", "hero-chevron-left",
       "Back link, previous page"},
      {"chevron-right", "hero-chevron-right-micro", "hero-chevron-right-mini",
       "hero-chevron-right", "Breadcrumb separator, next page"},
      {"chevron-down", "hero-chevron-down-micro", "hero-chevron-down-mini", "hero-chevron-down",
       "Details and menus that open"},
      {"arrow-top-right-on-square", "hero-arrow-top-right-on-square-micro",
       "hero-arrow-top-right-on-square-mini", "hero-arrow-top-right-on-square",
       "A link that leaves SAR Duty, such as Open in D4H"},
      {"arrow-path", "hero-arrow-path-micro", "hero-arrow-path-mini", "hero-arrow-path",
       "Refresh from D4H"},
      {"arrow-down-tray", "hero-arrow-down-tray-micro", "hero-arrow-down-tray-mini",
       "hero-arrow-down-tray", "Download a file, such as a letter PDF"},
      {"plus", "hero-plus-micro", "hero-plus-mini", "hero-plus",
       "Add a clause or a qualification"},
      {"bars-3", "hero-bars-3-micro", "hero-bars-3-mini", "hero-bars-3",
       "Open the top bar's menu on a phone"},
      {"x-mark", "hero-x-mark-micro", "hero-x-mark-mini", "hero-x-mark",
       "Close a toast, remove a chip, close the phone menu"},
      {"check-circle", "hero-check-circle-micro", "hero-check-circle-mini", "hero-check-circle",
       "Success banners and toasts"},
      {"information-circle", "hero-information-circle-micro", "hero-information-circle-mini",
       "hero-information-circle", "Info banners and toasts"},
      {"exclamation-triangle", "hero-exclamation-triangle-micro",
       "hero-exclamation-triangle-mini", "hero-exclamation-triangle",
       "Warning banners and warning text"},
      {"exclamation-circle", "hero-exclamation-circle-micro", "hero-exclamation-circle-mini",
       "hero-exclamation-circle", "Error banners, toasts, and error summaries"}
    ]
  end

  def button_kinds do
    [
      {:primary, "Primary"},
      {:secondary, "Secondary"},
      {:success, "Success"},
      {:danger, "Danger"},
      {:link, "Link"}
    ]
  end

  # The tags table on the Buttons and tags page, one row per <.badge> kind.
  def tag_kinds do
    [
      %{
        kind: :default,
        sample: "Not published",
        look: "Tinted grey",
        means: "A plain state. Nothing to do.",
        examples: "Draft, Not published, Inactive"
      },
      %{
        kind: :primary,
        sample: "Refreshed",
        look: "Tinted blue",
        means: "Worth knowing, not a problem.",
        examples: "New, Refreshed, Team admin"
      },
      %{
        kind: :success,
        sample: "Qualified",
        look: "Tinted green",
        means: "Good, done, or meets the rule.",
        examples: "Qualified, Letter sent, Active"
      },
      %{
        kind: :warning,
        sample: "12 days",
        look: "Solid amber",
        means: "Needs action soon.",
        examples: "Expires in 12 days, Missing hours, Key owner leaving"
      },
      %{
        kind: :danger,
        sample: "Expired",
        look: "Solid red",
        means: "Wrong or blocked now.",
        examples: "Expired, Not signed up, D4H key rejected"
      },
      %{
        kind: :outline,
        sample: "Primary hours",
        look: "Outlined",
        means: "A tag from D4H. Data, not status.",
        examples: "Whatever D4H holds: Rope, Marine, Avalanche"
      },
      %{
        kind: :kinds,
        look: "Solid, D4H colours",
        means: "The kind of activity, shown on its own, such as beside a title.",
        examples: "Only these three words"
      },
      %{
        kind: :markers,
        look: "Marker",
        means: "The kind of activity in a table column, where every row has one.",
        examples: "Only these three words"
      }
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
  # [{group, [{token, light, dark, use}]}]. The guide loads the app's stylesheet, so its
  # swatches are the app's colours.
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

  defdelegate chart_columns(), to: SampleData
  defdelegate chart_hours(), to: SampleData
  defdelegate chart_days(), to: SampleData
  defdelegate chart_week(), to: SampleData
  defdelegate chart_members(), to: SampleData
  defdelegate chart_map(), to: SampleData

  defdelegate letters(), to: SampleData
  defdelegate sample_page(), to: SampleData
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

  defdelegate activities(), to: SampleData
  defdelegate sample_team(), to: SampleData
  defdelegate sample_user(), to: SampleData
end
