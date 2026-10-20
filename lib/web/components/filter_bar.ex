defmodule Web.Components.FilterBar do
  @moduledoc """
  The search and filters above a long list (#350). See /styles/filter-bar.
  """
  use Phoenix.Component

  import Web.Components.Core

  alias Phoenix.LiveView.JS

  @doc """
  Renders a search box and menus above a list, then a line with the count.

  On a wide screen the menus sit in one row, each with its label inside, and a menu not
  at its default turns blue. A page with many menus marks the less common ones `more`:
  they wait behind a More filters button until one is on, so the row doesn't wrap. On a phone a Filters button shows them, and the filters that
  are on show as chips that remove them. The list's column headers sort it, so the bar has
  no sort menu: put the sort in `hidden` so a change keeps it.

  ## Examples

      <.filter_bar
        for={@form}
        id="activity_filter_form"
        count="212 activities"
        clear={@path_fn.(:all)}
        path_fn={@path_fn}
        page={@paginated}
        hidden={[@form[:sort]]}
      >
        <:search field={@form[:q]} />
        <:filter field={@form[:activity]} label="Kind" options={kinds()} default="all" />
      </.filter_bar>
  """
  attr :for, :any, required: true, doc: "the filter form, from to_form/2"
  attr :id, :string, required: true, doc: "the form's id"
  attr :count, :string, required: true, doc: "what the list shows, such as \"212 activities\""
  attr :total, :string, default: nil, doc: "a total after the count, such as \"40 hours total\""
  attr :clear, :string, default: nil, doc: "the list's path with no filters or search"

  attr :path_fn, :any,
    default: nil,
    doc: "builds the list's path with some options changed, for a chip that removes one"

  attr :page, App.Page, default: nil, doc: "the page shown, when the list pages"
  attr :hidden, :list, default: [], doc: "fields the form keeps but doesn't show, such as sort"
  attr :rest, :global, doc: "more attributes for the form"

  slot :lead, doc: "something before the search box, such as a view switch"

  slot :search do
    attr :field, Phoenix.HTML.FormField, required: true
    attr :placeholder, :string
  end

  slot :filter do
    attr :field, Phoenix.HTML.FormField, required: true
    attr :label, :string, required: true
    attr :options, :list, required: true
    attr :default, :string, required: true, doc: "the value that filters nothing"

    attr :type, :string,
      values: ["select", "combobox"],
      doc: "combobox for a long list, with All as its empty option and a default of \"\""

    attr :more, :boolean,
      doc: "behind More filters on a wide screen while at its default; on a phone, as any"
  end

  def filter_bar(assigns) do
    filters = Enum.map(assigns.filter, &mark/1)

    on = Enum.filter(filters, & &1.on?)
    searching? = Enum.any?(assigns.search, &(blank(&1.field.value) != ""))

    assigns =
      assign(assigns,
        filters: filters,
        on: on,
        clear?: assigns.clear != nil and (on != [] or searching?),
        clear_label: if(on == [], do: "Clear search", else: "Clear filters"),
        toggle: JS.toggle_class("is-open", to: "##{assigns.id}"),
        more?: Enum.any?(filters, & &1.more?)
      )

    ~H"""
    <.filter_form for={@for} id={@id} class="filter-bar" {@rest}>
      <input :for={field <- @hidden} type="hidden" name={field.name} value={field.value} />
      {render_slot(@lead)}
      <div :for={search <- @search} class="filter-bar-search">
        <.icon name="hero-magnifying-glass-mini" class="filter-bar-search-icon" />
        <input
          type="search"
          id={search.field.id}
          name={search.field.name}
          value={search.field.value}
          placeholder={search[:placeholder] || "Search"}
          aria-label="Search"
          phx-debounce="300"
        />
      </div>
      <button
        :if={@filters != []}
        type="button"
        class="btn filter-bar-toggle"
        aria-controls={"#{@id}-menus"}
        aria-expanded="false"
        phx-click={@toggle |> JS.toggle_attribute({"aria-expanded", "true", "false"})}
      >
        <.icon name="hero-funnel-mini" />Filters
        <span :if={@on != []} class="filter-bar-count">{length(@on)}</span>
      </button>
      <div :if={@filters != []} id={"#{@id}-menus"} class="filter-bar-menus">
        <.filter_menu :for={filter <- @filters} filter={filter} />
        <button
          :if={@more?}
          type="button"
          id={"#{@id}-more"}
          class="btn filter-bar-more"
          aria-expanded="false"
          phx-click={
            JS.toggle_class("is-more-open", to: "##{@id}")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
        >
          More filters <.icon name="hero-chevron-down-mini" />
        </button>
        <div class="filter-bar-done">
          <.link :if={@clear?} patch={@clear} class="link">Clear filters</.link>
          <button
            type="button"
            class="btn btn-primary"
            phx-click={
              @toggle
              |> JS.set_attribute({"aria-expanded", "false"}, to: "##{@id} .filter-bar-toggle")
            }
          >
            Show {@count}
          </button>
        </div>
      </div>
    </.filter_form>

    <div :if={@on != [] and @path_fn} class="filter-bar-chips">
      <.link
        :for={filter <- @on}
        patch={@path_fn.(remove(filter, @page))}
        class="chip"
        aria-label={"Remove filter #{filter.label}: #{option_label(filter)}"}
      >
        <span class="text-text-muted">{filter.label}</span>
        {option_label(filter)}
        <.icon name="hero-x-mark-micro" />
      </.link>
    </div>

    <div class="table-summary" id={"#{@id}-summary"}>
      <span>
        <strong class="text-text">{@count}</strong>
        <span :if={@total}>· {@total}</span>
        <span :if={@clear?}>· <.link patch={@clear} class="link">{@clear_label}</.link></span>
      </span>
      <span :if={@page && @page.total_pages > 1}>{range(@page)}</span>
    </div>
    """
  end

  attr :filter, :map, required: true

  defp filter_menu(%{filter: %{type: "combobox"}} = assigns) do
    ~H"""
    <div class={[
      "filter-menu filter-menu-combobox",
      @filter.on? && "is-on",
      @filter.more? && "is-more"
    ]}>
      <label for={@filter.field.id} class="filter-menu-label">{@filter.label}</label>
      <.combobox
        id={@filter.field.id}
        name={@filter.field.name}
        value={@filter.field.value}
        options={@filter.options}
        prompt="All"
        placeholder="All"
        clearable
      />
    </div>
    """
  end

  defp filter_menu(assigns) do
    ~H"""
    <div class={["filter-menu", @filter.on? && "is-on", @filter.more? && "is-more"]}>
      <label for={@filter.field.id} class="filter-menu-label">{@filter.label}</label>
      <select id={@filter.field.id} name={@filter.field.name}>
        {Phoenix.HTML.Form.options_for_select(@filter.options, blank(@filter.field.value))}
      </select>
    </div>
    """
  end

  # A `more` filter waits behind More filters only while it filters nothing.
  defp mark(filter) do
    on? = on?(filter)
    Map.merge(filter, %{on?: on?, more?: filter[:more] == true and not on?})
  end

  defp on?(filter), do: blank(filter.field.value) not in ["", filter.default]

  defp blank(nil), do: ""
  defp blank(value), do: to_string(value)

  # The options with the filter's default taken off, and the first page, since the old
  # page may be past the end of a longer list.
  defp remove(filter, page) do
    [{filter.field.field, filter.default}] ++ if(page, do: [page: 1], else: [])
  end

  defp option_label(filter), do: option_label(filter.options, blank(filter.field.value))

  defp option_label(options, value) do
    Enum.find_value(options, value, fn
      {label, option} -> to_string(option) == value && label
      option -> to_string(option) == value && option
    end)
  end

  @doc "The rows a page shows, out of them all: \"51–100 of 1,912\"."
  def range(%App.Page{} = page) do
    first = (page.page_number - 1) * page.page_size + 1
    last = min(page.page_number * page.page_size, page.total_entries)
    format = &Service.Format.number/1
    "#{format.(first)}–#{format.(last)} of #{format.(page.total_entries)}"
  end
end
