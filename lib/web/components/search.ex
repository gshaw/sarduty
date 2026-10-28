defmodule Web.Components.Search do
  @moduledoc """
  The top bar's search (#473): a field on a desktop, opening a panel under it, and a
  magnifying glass below 1024px, opening a sheet over the page with the keyboard up. Both
  are this markup; the CSS decides which shows. Web.Components.SearchBox runs it on team
  pages, and Web.StyleGuideSearchLive in the style guide, with its own results. See
  /styles/search and docs/search.md.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [icon: 1]

  alias Phoenix.LiveView.JS
  alias Service.Format
  alias Web.Components.Standing

  @kind_names %{
    member: "Members",
    activity: "Activities",
    equipment: "Equipment",
    qualification: "Qualifications",
    group: "Groups",
    endorsement: "Endorsements",
    template: "Templates",
    chore: "Chores",
    certificate: "Certificates",
    page: "Pages",
    recent: "Recent"
  }

  attr :id, :string, default: "search"
  attr :query, :string, default: ""
  attr :groups, :list, default: [], doc: "from Web.Search.run/3"
  attr :kinds, :list, default: [], doc: "what this person can find, for the hint"
  attr :team, :map, default: nil
  attr :target, :any, default: nil, doc: "the LiveComponent the form's events go to"
  attr :recent, :list, default: [], doc: "from Web.Search.recent/3, shown before typing"

  attr :recent_key, :string,
    default: nil,
    doc: "where the browser keeps this person's recent picks on this team"

  attr :open, :boolean,
    default: false,
    doc: "drawn open, as the style guide shows it; in the app the hook opens it"

  # A search of something other than a team's records, such as the style guide's, says
  # what it finds with these. A group may name itself with `heading`, and a hit may carry
  # a `snippet`, the text it matched.
  attr :placeholder, :string, default: "Search members, activities…"
  attr :hint, :string, default: nil, doc: "before typing; by default, from kinds"
  attr :none_help, :list, default: nil, doc: "paragraphs under Nothing matches"

  attr :live_links, :boolean,
    default: true,
    doc: "results open with live navigation; false on pages that aren't LiveViews"

  attr :word_starts, :boolean,
    default: false,
    doc: "bold where a word starts, for a search that matches only there"

  def search_box(assigns) do
    ~H"""
    <div
      id={@id}
      class={["site-search", @open && "is-open"]}
      phx-hook="Search"
      phx-mounted={JS.ignore_attributes("class")}
      phx-target={@target}
      data-recent-key={@recent_key}
    >
      <button
        type="button"
        id={"#{@id}-open"}
        class="site-bar-search"
        aria-label="Search"
      >
        <.icon name="search" />
      </button>
      <div class="site-search-dim" phx-click={close(@id)}></div>
      <div class="site-search-box">
        <form
          id={"#{@id}-form"}
          role="search"
          class="site-search-form"
          phx-change="search"
          phx-submit="open"
          phx-target={@target}
        >
          <label class="site-bar-search-field">
            <.icon name="search" />
            <input
              id={"#{@id}-input"}
              name="q"
              type="search"
              value={@query}
              placeholder={@placeholder}
              autocomplete="off"
              autocapitalize="off"
              spellcheck="false"
              enterkeyhint="go"
              phx-debounce="150"
              role="combobox"
              aria-label="Search"
              aria-autocomplete="list"
              aria-controls={"#{@id}-results"}
              aria-expanded={to_string(@open)}
            />
            <button
              type="button"
              id={"#{@id}-clear"}
              class="site-search-clear"
              aria-label="Clear search"
            >
              <.icon name="x" />
            </button>
            <kbd class="site-search-key" aria-hidden="true">/</kbd>
          </label>
          <button type="button" class="site-search-cancel" phx-click={close(@id)}>
            Cancel
          </button>
        </form>
        <div class="site-search-panel">
          <.search_results
            id={@id}
            query={@query}
            groups={@groups}
            recent={@recent}
            kinds={@kinds}
            team={@team}
            hint={@hint}
            none_help={@none_help}
            live_links={@live_links}
            word_starts={@word_starts}
          />
          <p
            :if={@groups != [] or (@recent != [] and @query in [nil, ""])}
            class="site-search-keys"
            aria-hidden="true"
          >
            <span><kbd>↑</kbd> <kbd>↓</kbd> move</span>
            <span><kbd>Enter</kbd> open</span>
            <span><kbd>Esc</kbd> close</span>
          </p>
        </div>
      </div>
    </div>
    """
  end

  @doc "Closes the search, leaving what was typed."
  def close(id \\ "search"),
    do:
      JS.remove_class("is-open", to: "##{id}")
      |> JS.dispatch("sarduty:search-closed", to: "##{id}")

  attr :id, :string, required: true
  attr :query, :string, required: true
  attr :groups, :list, required: true
  attr :recent, :list, required: true
  attr :kinds, :list, required: true
  attr :team, :map, required: true
  attr :hint, :string, required: true
  attr :none_help, :list, required: true
  attr :live_links, :boolean, required: true
  attr :word_starts, :boolean, required: true

  # Before typing: the recent picks, then what search finds. After: the results.
  defp search_results(assigns) do
    terms = App.ViewData.Search.terms(assigns.query)
    shown = if terms == [], do: assigns.recent, else: assigns.groups

    groups =
      for group <- shown,
          do: Map.put(group, :more_path, more_path(group, terms, assigns.team, assigns.query))

    assigns = assign(assigns, terms: terms, groups: groups)

    ~H"""
    <div :if={@groups != []} id={"#{@id}-results"} role="listbox" aria-label="Search results">
      <section
        :for={group <- @groups}
        id={"#{@id}-group-#{group.kind}"}
        class="site-search-group"
        role="group"
        aria-labelledby={"#{@id}-heading-#{group.kind}"}
      >
        <h2 id={"#{@id}-heading-#{group.kind}"}>{group_heading(group)}</h2>
        <.hit
          :for={hit <- group.hits}
          id={"#{@id}-hit-#{hit.kind}-#{hit.id}"}
          kind={hit.kind}
          hit={hit}
          terms={@terms}
          team={@team}
          live_links={@live_links}
          word_starts={@word_starts}
        />
        <.link
          :if={group.more_path}
          id={"#{@id}-more-#{group.kind}"}
          navigate={group.more_path}
          class="site-search-more"
        >
          All {String.downcase(Map.fetch!(kind_names(), group.kind))} with “{@query}”
        </.link>
      </section>
    </div>
    <p :if={@terms == []} id={"#{@id}-hint"} class="site-search-hint">
      {@hint || hint(@kinds)}
    </p>
    <div :if={@terms != [] and @groups == []} id={"#{@id}-none"} class="site-search-none">
      <h2>Nothing matches “{@query}”</h2>
      <%= if @none_help do %>
        <p :for={help <- @none_help}>{help}</p>
      <% else %>
        <p>
          Search looks at names, ID numbers, barcodes, and serial numbers. Check the spelling, or try fewer words.
        </p>
        <p>
          SAR Duty refreshes every 10 minutes, so something just added may not be here yet.
        </p>
      <% end %>
    </div>
    """
  end

  @doc "Each kind's heading."
  def kind_names, do: @kind_names

  defp group_heading(%{heading: heading}), do: heading
  defp group_heading(group), do: Map.fetch!(@kind_names, group.kind)

  # The list filters by the whole search as typed, so its All link only matches what search
  # found when the search is one word.
  defp more_path(%{more?: true, kind: kind}, [_one], team, query),
    do: Web.Search.more_path(kind, team, query)

  defp more_path(_group, _terms, _team, _query), do: nil

  attr :id, :string, required: true
  attr :kind, :atom, required: true
  attr :hit, :map, required: true
  attr :terms, :list, required: true
  attr :team, :map, required: true
  attr :live_links, :boolean, required: true
  attr :word_starts, :boolean, required: true

  defp hit(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={if @live_links, do: @hit.path}
      href={if !@live_links, do: @hit.path}
      class="site-search-hit"
      role="option"
      aria-selected="false"
      data-key={Web.Search.key(@hit)}
    >
      <span :if={@kind == :member} class="avatar">{Web.Navigation.initials(@hit.title)}</span>
      <span class="site-search-text">
        <span class="site-search-title">{bold_terms(@hit.title, @terms, @word_starts)}</span>
        <.hit_line kind={@kind} hit={@hit} team={@team} terms={@terms} word_starts={@word_starts} />
      </span>
    </.link>
    """
  end

  attr :kind, :atom, required: true
  attr :hit, :map, required: true
  attr :team, :map, required: true
  attr :terms, :list, required: true
  attr :word_starts, :boolean, required: true

  defp hit_line(%{hit: %{snippet: _snippet}} = assigns) do
    ~H"""
    <span :if={@hit.snippet not in [nil, ""]} class="site-search-line">
      {bold_terms(@hit.snippet, @terms, @word_starts)}
    </span>
    """
  end

  defp hit_line(%{kind: :activity} = assigns) do
    ~H"""
    <span class="site-search-line">
      <span class={["marker", "marker-#{@hit.activity_kind}"]}>
        {String.capitalize(@hit.activity_kind || "")}
      </span>
      · #{@hit.ref_id}
      <span :if={@hit.started_at}>· {Format.date_short(@hit.started_at, @team.timezone)}</span>
    </span>
    """
  end

  defp hit_line(assigns) do
    assigns = assign(assigns, line: line(assigns.kind, assigns.hit))

    ~H"""
    <span :if={@line != ""} class="site-search-line">{@line}</span>
    """
  end

  defp line(:member, hit), do: join([hit.position, standing(hit.standing)])

  defp line(:equipment, hit),
    do:
      join([
        hit.barcode,
        hit.location_title,
        if(!hit.in_service?, do: String.capitalize(hit.status))
      ])

  defp line(:chore, hit),
    do:
      join([
        hit.member_name,
        Format.date_short(hit.date),
        if(hit.status != :accepted, do: hit.status |> Atom.to_string() |> String.capitalize())
      ])

  defp line(:certificate, hit),
    do:
      join([
        hit.member_name,
        if(hit.status != :accepted, do: hit.status |> Atom.to_string() |> String.capitalize())
      ])

  defp line(_kind, _hit), do: ""

  defp standing(:active), do: nil
  defp standing({:away, until}), do: "Away until #{Format.date_short(until)}"
  defp standing(standing), do: Standing.text(standing)

  defp join(parts), do: parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ")

  @doc """
  Pure. The title in pieces, `{bold?, text}`, with the first place each word typed appears
  in bold, or with `word_starts?` the first place it starts a word. A title whose lowercase
  changes its length stays plain.
  """
  def highlight(title, terms, word_starts? \\ false) do
    lower = String.downcase(title)

    if byte_size(lower) == byte_size(title) do
      terms
      |> Enum.flat_map(&first_match(lower, &1, word_starts?))
      |> merge_ranges()
      |> pieces(title)
    else
      [{false, title}]
    end
  end

  # highlight/3 as HTML, every piece escaped. Built here, not in the template, so the
  # formatter can't put spaces between the pieces.
  defp bold_terms(title, terms, word_starts?) do
    {:safe,
     for {bold?, text} <- highlight(title, terms, word_starts?) do
       {:safe, escaped} = Phoenix.HTML.html_escape(text)
       if bold?, do: ["<b>", escaped, "</b>"], else: escaped
     end}
  end

  defp first_match(lower, term, false) do
    case :binary.match(lower, term) do
      {start, length} -> [{start, start + length}]
      :nomatch -> []
    end
  end

  defp first_match(lower, term, true) do
    for {start, length} <- :binary.matches(lower, term),
        App.ViewData.Search.starts_word_at?(lower, start),
        reduce: [] do
      [] -> [{start, start + length}]
      found -> found
    end
  end

  # Plain, bold, plain, … from each range's ends, then the plain rest.
  defp pieces(ranges, title) do
    cuts = Enum.flat_map(ranges, fn {from, to} -> [from, to] end)
    ends = Enum.concat(cuts, [byte_size(title)])

    [0 | cuts]
    |> Enum.zip(ends)
    |> Enum.with_index()
    |> Enum.map(fn {{from, to}, index} ->
      {rem(index, 2) == 1, binary_part(title, from, to - from)}
    end)
    |> Enum.reject(fn {_bold?, text} -> text == "" end)
  end

  defp merge_ranges(ranges) do
    ranges
    |> Enum.sort()
    |> Enum.reduce([], fn
      {from, to}, [{last_from, last_to} | rest] when from <= last_to ->
        [{last_from, max(to, last_to)} | rest]

      range, acc ->
        [range | acc]
    end)
    |> Enum.reverse()
  end

  # What this person can find, from the kinds they see.
  defp hint(kinds) do
    things = for kind <- kinds, do: @kind_names |> Map.fetch!(kind) |> String.downcase()

    by =
      if :equipment in kinds,
        do: "name, ID number, barcode, or serial number",
        else: "name or ID number"

    "Find #{list(things)} by #{by}."
  end

  defp list([one]), do: one
  defp list([one, two]), do: "#{one} and #{two}"
  defp list(many), do: (many |> Enum.drop(-1) |> Enum.join(", ")) <> ", and " <> List.last(many)
end
