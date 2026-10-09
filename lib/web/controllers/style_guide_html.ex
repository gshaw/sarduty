defmodule Web.StyleGuideHTML do
  use Web, :html

  import Web.Components.ActivityMap, only: [activity_map: 1]
  import Web.Components.ActivityFilterTable, only: [activity_table: 1]
  import Web.Components.AttendanceImport
  import Web.Components.Breadcrumbs
  import Web.Components.Chart
  import Web.Components.D4H
  import Web.Components.GroupRule
  import Web.Components.Pagination
  import Web.Components.RowLink
  import Web.Components.Scanner
  import Web.Components.Table

  alias Web.StyleGuideHTML.SampleData

  # Pages take a suffix, so the Button page doesn't clash with <.button>.
  embed_templates "style_guide_html/*"
  embed_templates "style_guide_html/pages/*", suffix: "_page"

  # The Writing page shows docs/writing.md, so agents and the guide read the same rules.
  @writing_path Path.expand("../../../docs/writing.md", __DIR__)
  @external_resource @writing_path
  @writing_html @writing_path
                |> File.read!()
                |> MDEx.to_html!(extension: [table: true, tasklist: true, header_id_prefix: ""])

  def writing_html, do: Phoenix.HTML.raw(@writing_html)

  # cspell:ignore HETS

  # The guide's groups, in the bar's order: {group, title, about, [{page, title, about}]}.
  # A group lists its pages at /styles/<group>, A to Z after Get started. A page is also
  # its template name, and its path is the name with dashes.
  def groups do
    [
      {:index, "Get started", "What the guide is for and the principles behind it.",
       [{:index, "Overview", "What the guide is for and the principles behind it."}]},
      {:foundations, "Foundations", "What every page shares: colour, type, space, and words.",
       [
         {:colour, "Colour", "Every token in light and dark, what each is for, and its class."},
         {:focus, "Focus", "The yellow keyboard focus on everything you can reach."},
         {:icons, "Icons", "The small set of icons, their sizes, and when to use one."},
         {:layout, "Layout", "The page header, how wide content goes, and the layout classes."},
         {:logo, "Logo", "The logo's forms, sizes, and files."},
         {:spacing, "Spacing", "The 8 spaces on a 4px grid, and their classes."},
         {:typography, "Typography", "The type scale, headings, body text, numbers, and links."},
         {:writing, "Writing",
          "The rules and glossary for every word a person reads. Agents follow it."}
       ]},
      {:components, "Components", "The parts pages are built from, one per page.",
       [
         {:back_link, "Back link", "A way back for pages outside the main tree."},
         {:band, "Band", "The result of a check, big and in colour."},
         {:banner, "Banner", "Something true about the page until it changes."},
         {:breadcrumbs, "Breadcrumbs", "Where a page sits under its section."},
         {:button, "Button", "Kinds, sizes, states, and rows of buttons."},
         {:callout, "Callout", "Advice set apart beside a form field."},
         {:card, "Card", "A box for one topic: on a dashboard, or under a result."},
         {:chart, "Chart", "Columns, lines, a calendar, a week grid, and a bar list."},
         {:confirm_dialog, "Confirm dialog", "A question before a change that can't be undone."},
         {:detail_list, "Detail list", "Key facts about one record."},
         {:empty_state, "Empty state", "Why a list is empty and what to do."},
         {:error_summary, "Error summary", "What to fix in a form after a failed save."},
         {:forms, "Forms",
          "Every input: text, select, date, text area, checkboxes, radios, and switches."},
         {:map, "Map", "A dot per activity on a Mapbox map."},
         {:pagination, "Pagination", "Pages under a long table."},
         {:qr_scanner, "QR scanner", "Scan ID cards with the phone's camera."},
         {:row_link, "Row link", "A list row that goes to one place."},
         {:spinner, "Spinner", "Says what slow thing is happening."},
         {:stat, "Stat", "A number, what it counts, and how it compares."},
         {:table, "Table", "Dense rows, sorting, and header groups."},
         {:tabs, "Tabs", "Pages about one record, a link each."},
         {:tag, "Tag", "A word or two of status."},
         {:toast, "Toast", "The result of what the person did. It comes and goes."},
         {:top_bar, "Top bar", "The main sections and the account menu."},
         {:warning_text, "Warning text", "A consequence people must know before they act."}
       ]},
      {:patterns, "Patterns", "Whole screens from the app, built from the components.",
       [
         {:build_a_group_rule, "Build a group rule", "An editor inside a page."},
         {:filter_a_list, "Filter a list", "Filters, a summary line, a table, and pages."},
         {:fix_form_errors, "Fix form errors", "A settings form after a failed save."},
         {:paste_a_report, "Paste a report", "Turn a pasted attendance report into changes."},
         {:review_changes, "Review changes", "Check the changes to make, then send them."}
       ]}
    ]
  end

  def page_path(:index), do: "/styles"
  def page_path(page), do: "/styles/" <> (page |> Atom.to_string() |> String.replace("_", "-"))

  # What /styles/<slug> shows: {:group, group}, {:page, template}, or nil. A page's template
  # is its name with _page, as embed_templates names it.
  def find(slug) do
    path = "/styles/" <> slug

    Enum.find_value(groups(), fn {group, _title, _about, pages} = g ->
      if group != :index && page_path(group) == path,
        do: {:group, g},
        else: find_page(pages, path)
    end)
  end

  defp find_page(pages, path) do
    Enum.find_value(pages, fn {page, _title, _about} ->
      page != :index && page_path(page) == path &&
        {:page, String.to_existing_atom("#{page}_page")}
    end)
  end

  # The group a page or group belongs to, for the bar's tabs and the side nav.
  def group_of(current) do
    Enum.find(groups(), fn {group, _title, _about, pages} ->
      group == current || Enum.any?(pages, &(elem(&1, 0) == current))
    end)
  end

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
       "Success banners, toasts, and bands"},
      {"information-circle", "hero-information-circle-micro", "hero-information-circle-mini",
       "hero-information-circle", "Info banners and bands"},
      {"exclamation-triangle", "hero-exclamation-triangle-micro",
       "hero-exclamation-triangle-mini", "hero-exclamation-triangle",
       "Warning banners, warning text, and bands"},
      {"exclamation-circle", "hero-exclamation-circle-micro", "hero-exclamation-circle-mini",
       "hero-exclamation-circle", "Danger banners, error toasts, and bands"},
      {"arrow-right-end-on-rectangle", "hero-arrow-right-end-on-rectangle-micro",
       "hero-arrow-right-end-on-rectangle-mini", "hero-arrow-right-end-on-rectangle",
       "A member arrived, at the door"},
      {"arrow-left-start-on-rectangle", "hero-arrow-left-start-on-rectangle-micro",
       "hero-arrow-left-start-on-rectangle-mini", "hero-arrow-left-start-on-rectangle",
       "A member left, at the door"}
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

  # The tags table on the Tag page, one row per <.badge> kind.
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
      {3, 12, "Table cell sides, a picture to its words"},
      {4, 16, "Paragraph spacing, card padding, title to content"},
      {6, 24, "Between form fields, page gutter"},
      {8, 32, "Between sections of a page, page bottom"},
      {12, 48, "Above a section heading in the guide"},
      {16, 64, "Top of a page, under the top bar"}
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

  # The class a token is most often used as: text for text colours, border for rules, and
  # bg for surfaces and fills. Any property works: border-danger-text, text-incident.
  @text_tokens ~w(text text-muted link link-hover success-text danger-text)
  @border_tokens ~w(border border-subtle)

  def token_class(token) when token in @text_tokens, do: "text-" <> token
  def token_class(token) when token in @border_tokens, do: "border-" <> token
  def token_class(token), do: "bg-" <> token

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
  defdelegate settings_form(), to: SampleData

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
