defmodule Web.StyleGuideHTML do
  use Web, :html

  import Web.Components.ActivityMap, only: [activity_map: 1]
  import Web.Components.ActivityPanel
  import Web.Components.ActivityFilterTable, only: [activity_table: 1]
  import Web.Components.Breadcrumbs
  import Web.Components.Chart
  import Web.Components.CopyButton
  import Web.Components.D4H
  import Web.Components.EmailPreview
  import Web.Components.FileDrop
  import Web.Components.FilterBar
  import Web.Components.GroupRule
  import Web.Components.HeadingRow
  import Web.Components.MemberLetter
  import Web.Components.MilestoneList
  import Web.Components.OpenInMaps
  import Web.Components.Pagination
  import Web.Components.PersonHead
  import Web.Components.Email
  import Web.Components.Phone, only: [phone: 1]
  import Web.Components.Place, only: [place_field: 1]
  import Web.Components.Reply, only: [reply: 1]
  import Web.Components.RowLink
  import Web.Components.Search, only: [search_box: 1]
  import Web.Components.Scanner
  import Web.Components.StatSwitch
  import Web.Components.Table

  alias App.Mailer.ActivityMailer
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

  # The guide's groups, in the side nav's order: {group, title, about, [{page, title, about}]}.
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
         {:values, "Values", "Every formatter for dates, times, numbers, and quantities."},
         {:writing, "Writing",
          "The rules and glossary for every word a person reads. Agents follow it."}
       ]},
      {:components, "Components", "The parts pages are built from, one per page.",
       [
         {:activity_panel, "Activity panel", "An activity's day and time, counts, and reply."},
         {:band, "Band", "The result of a check, big and in colour."},
         {:banner, "Banner", "Something true about the page until it changes."},
         {:breadcrumbs, "Breadcrumbs", "Where a page sits under its section."},
         {:button, "Button", "Kinds, sizes, states, and rows of buttons."},
         {:callout, "Callout", "Advice set apart beside a form field."},
         {:card, "Card", "A box for one topic: on a dashboard, or under a result."},
         {:chart, "Chart", "Columns, lines, a calendar, a week grid, and a bar list."},
         {:combobox, "Combobox", "A select you type into, for a long list."},
         {:confirm_dialog, "Confirm dialog", "A question before a change that can't be undone."},
         {:copy_button, "Copy button", "Copies the value before it."},
         {:detail_list, "Detail list", "Key facts about one record."},
         {:email, "Email", "An email address to reach someone by, with a copy button."},
         {:email_preview, "Email preview", "An email as members get it, before it's sent."},
         {:empty_state, "Empty state", "Why a list is empty and what to do."},
         {:error_summary, "Error summary", "What to fix in a form after a failed save."},
         {:file_drop, "File drop", "Drop, paste, or select a file to upload."},
         {:filter_bar, "Filter bar", "Search and filters above a long list."},
         {:forms, "Forms",
          "Every input: text, select, date, text area, checkboxes, radios, and switches."},
         {:heading_row, "Heading row", "A heading with its action, and a note."},
         {:map, "Map", "A dot per activity on a Mapbox map."},
         {:member_letter, "Member letter", "A member's tax credit letter for a year."},
         {:milestone_list, "Milestone list", "What a member reached, and the day."},
         {:open_in_maps, "Open in maps", "A place in the account's maps app."},
         {:pagination, "Pagination", "Pages under a long table."},
         {:person_head, "Person head", "A member's photo, name, standing, and facts."},
         {:phone, "Phone", "A phone number with a copy button, and Call and Text buttons."},
         {:place, "Place", "An address box that finds places and takes a pin."},
         {:qr_scanner, "QR scanner", "Scan ID cards with the phone's camera."},
         {:reply, "Reply", "A member's answer to an invitation."},
         {:rich_text, "Rich text", "Text with bold, italics, links, and lists."},
         {:row_link, "Row link", "A list row that goes to one place."},
         {:search, "Search", "Find a team's records and pages from the top bar."},
         {:side_nav, "Side navigation", "An area's pages, down the left of each page in it."},
         {:spinner, "Spinner", "Says what slow thing is happening."},
         {:stat, "Stat", "A number, what it counts, and how it compares."},
         {:stat_switch, "Stat switch", "A list's split as counts, each one a filter."},
         {:table, "Table", "Dense rows, sorting, header groups, and row groups."},
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
         {:fix_form_errors, "Fix form errors", "A settings form after a failed save."}
       ]}
    ]
  end

  def page_path(:index), do: "/styles"
  def page_path(page), do: "/styles/" <> (page |> Atom.to_string() |> String.replace("_", "-"))

  # What /styles/<slug> shows: {:group, group}, {:page, page}, or nil.
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
      page != :index && page_path(page) == path && {:page, page}
    end)
  end

  # A page's template is its name with _page, as embed_templates names it.
  def template(page), do: String.to_existing_atom("#{page}_page")

  # The group a page or group belongs to, for the side nav and the breadcrumbs.
  def group_of(current) do
    Enum.find(groups(), fn {group, _title, _about, pages} ->
      group == current || Enum.any?(pages, &(elem(&1, 0) == current))
    end)
  end

  # A page's or group's title, for the browser tab and the breadcrumbs.
  def page_title(current) do
    {_group, title, _about, pages} = group_of(current)

    case List.keyfind(pages, current, 0) do
      {_page, page_title, _about} -> page_title
      nil -> title
    end
  end

  # The side nav and the phone's Menu: the 4 groups, the open one marked, then its pages.
  # Get started is one page, so it lists none. Links as Web.Navigation makes them.
  def nav_sections(current) do
    {open, _title, _about, pages} = group_of(current)

    groups =
      for {group, title, _about, _pages} <- groups(), do: nav_link(group, title, current, open)

    pages =
      for {page, title, _about} <- pages, open != :index, do: nav_link(page, title, current, nil)

    Enum.reject([groups, pages], &(&1 == []))
  end

  defp nav_link(key, label, current, open) do
    %{
      key: Atom.to_string(key),
      label: label,
      path: page_path(key),
      current: key == current,
      open: key == open and key != current,
      count: nil
    }
  end

  # Auto, Light, and Dark, at the foot of the side nav and the phone's Menu. The frame's
  # script marks the one in use and saves a choice.
  def theme_switch(assigns) do
    ~H"""
    <div class="guide-theme">
      <span>Theme</span>
      <div class="theme-switch" role="group" aria-label="Theme">
        <button type="button" data-theme-choice="">Auto</button>
        <button type="button" data-theme-choice="light">Light</button>
        <button type="button" data-theme-choice="dark">Dark</button>
      </div>
    </div>
    """
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

  # The icon set, one row per file in assets/icons, with its use.
  def icons do
    [
      {"chevron-left", "Back link, previous page"},
      {"chevron-right", "Breadcrumb separator, next page"},
      {"chevron-down", "Details and menus that open"},
      {"external-link",
       "A link that leaves SAR Duty, such as Open in D4H or Open in Google Maps"},
      {"copy", "Copy the value before it"},
      {"menu", "Open the top bar's menu on a phone"},
      {"x", "Close a toast, remove a chip, close the phone menu"},
      {"circle-check", "Success banners, toasts, and bands"},
      {"info", "Info banners and bands"},
      {"triangle-alert", "Warning banners, warning text, and bands"},
      {"circle-alert", "Danger banners, error toasts, and bands"},
      {"log-in", "Log in, and a member arrived on Take attendance"},
      {"log-out", "A member left, on Take attendance"},
      {"search", "Search, in the top bar and a filter bar"},
      {"funnel", "Filters, on a filter bar"},
      {"upload", "Drop a file, in a file drop"},
      {"file", "A file in a file drop that is not a photo"},
      {"calendar-plus", "Add to calendar"},
      {"clock", "Hours milestones"},
      {"cake", "Years milestones"},
      {"life-buoy", "Incidents milestones"},
      {"shield-check", "SAR Duty admin, in the team switcher"},
      {"building-complex", "An organization, in the team switcher"},
      {"scan-line", "Start scanning, on the QR scanner"},
      {"rotate-ccw-square", "Rotate left, a certificate photo"},
      {"rotate-cw-square", "Rotate right, a certificate photo"},
      {"bold", "Bold, in rich text"},
      {"italic", "Italic, in rich text"},
      {"link", "Link, in rich text"},
      {"list", "Bulleted list, in rich text"},
      {"list-ordered", "Numbered list, in rich text"}
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
        examples: "Expired, Not signed up, Key refused"
      },
      %{
        kind: :outline,
        sample: "Primary hours",
        look: "Outlined",
        means: "An activity's own tag. Data, not status.",
        examples: "Whatever the team uses: Rope, Marine, Avalanche"
      },
      %{
        kind: :kinds,
        look: "Solid, the kind's colour",
        means: "The kind of activity, shown on its own, such as beside a title.",
        examples: "Incident, Exercise, Event, and Chores for a chore activity"
      },
      %{
        kind: :markers,
        look: "Marker",
        means: "The kind of activity in a table column, where every row has one.",
        examples: "The same four words"
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

  defdelegate values, to: Web.StyleGuideHTML.Values, as: :all
  defdelegate value_rows(functions), to: Web.StyleGuideHTML.Values, as: :rows

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

  # An update as Send an update shows it, from the mailer's own HTML.
  def sample_update_email do
    ActivityMailer.update_preview(
      SampleData.panel_activity(),
      SampleData.sample_team(),
      %{name: "Avery Chen", email: "avery@example.com"},
      "Bring your harness and helmet. We meet at the Murrin Park lot, not the hall.",
      :signed_up
    )
  end

  defdelegate panel_activity(), to: SampleData
  defdelegate panel_now(), to: SampleData
  defdelegate panel_counts(), to: SampleData
  defdelegate sample_page(), to: SampleData
  defdelegate sample_filters(), to: SampleData
  defdelegate sample_filter_page(), to: SampleData
  defdelegate sample_kinds(), to: SampleData
  defdelegate sample_whens(), to: SampleData
  defdelegate sample_hours(), to: SampleData
  defdelegate sample_statuses(), to: SampleData
  defdelegate rule_sentence_rules(), to: SampleData
  defdelegate rule_rows(), to: SampleData
  defdelegate rule_options(), to: SampleData
  defdelegate qualification_options(), to: SampleData
  defdelegate settings_form(), to: SampleData

  def rule_preview do
    [
      {"Avery Chen",
       "Holds OFA Level 1 and GSAR Member, which meets both endorsements in the rule.",
       "Added Mar 2, 2024", nil},
      {"Casey Dhillon", "Wilderness First Aid expires Nov 12, 2025.",
       "Renewal course booked for Nov 1, 2025", 12},
      {"Devon Okafor", "No First Aid qualification.",
       "Last held OFA Level 1, expired Jun 30, 2024", nil}
    ]
  end

  defdelegate activities(), to: SampleData
  defdelegate sample_team(), to: SampleData
  defdelegate sample_user(), to: SampleData
  defdelegate sample_managed_teams(), to: SampleData
  defdelegate sample_member_logins(), to: SampleData
  defdelegate sample_switchers(), to: SampleData
  defdelegate sample_nav_area(), to: SampleData
  defdelegate sample_nav_sections(), to: SampleData
  defdelegate sample_member(), to: SampleData
  defdelegate sample_search_groups(), to: SampleData
  defdelegate sample_search_recent(), to: SampleData
  defdelegate place_form(values \\ %{}), to: SampleData
  defdelegate sample_past_places(), to: SampleData
  defdelegate sample_mapbox_places(), to: SampleData
end
