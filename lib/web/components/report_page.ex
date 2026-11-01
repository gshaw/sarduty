defmodule Web.Components.ReportPage do
  @moduledoc """
  A report run as a page (#784): the tiles, search box, filters, sortable headers, and
  pages its clauses draw (App.Report.View), around its rows. A report without them is
  its rows alone, with their count.

  On the report's page, each control is a link or a form whose change patches the URL.
  In the editor, `click` turns them into events, so a pick changes the preview, not the
  page. A list such as Activities draws its own cells in the `table` slot.
  """
  use Web, :function_component

  import Web.Components.FilterBar
  import Web.Components.Pagination
  import Web.Components.ReportTable
  import Web.Components.StatSwitch

  alias App.Report.View
  alias Phoenix.LiveView.JS
  alias Plug.Conn.Query
  alias Service.Format

  attr :id, :string, required: true
  attr :view, View, required: true
  attr :records, :map, required: true, doc: "from App.ViewData.ReportRecords.load/3"
  attr :team, :any, required: true
  attr :now, :any, required: true

  attr :path_fn, :any,
    default: nil,
    doc: "the page's path with picks changed, or `:clear` for none; nil in the editor"

  attr :form, :any, default: nil, doc: "the controls' form, from `controls_form/1`"
  attr :count, :string, default: nil, doc: "the line over the rows, when not the count"
  attr :marker, :any, default: nil, doc: "a tile's value to its marker, or nil for none"

  attr :combobox, :list,
    default: [],
    doc: "the filters drawn as a combobox, by name: those that list the team's own names"

  slot :table, doc: "the page's own table for the rows, in place of the report's cells"

  def report_page(assigns) do
    view = assigns.view
    switch_menu = switch_menu(view)
    filters = Enum.map(List.wrap(switch_menu) ++ view.filters, &menu(&1, assigns.combobox))

    assigns =
      assign(assigns,
        bar?: view.search? or filters != [],
        filters: filters,
        switch_menu?: switch_menu != nil
      )

    ~H"""
    <.stat_switch :if={@view.switch} id={"#{@id}-switch"} label={@view.switch.label}>
      <:view
        :for={tile <- @view.switch.tiles}
        id={"#{@id}-tile-#{tile.value}"}
        patch={@path_fn && @path_fn.([{@view.switch.name, tile.value}, page: nil])}
        click={!@path_fn && pick(@view.switch.name, tile.value)}
        current={@view.switch.picked == tile.value}
        count={tile.count}
        marker={@marker && @marker.(tile.value)}
      >
        {tile.label}
      </:view>
    </.stat_switch>

    <.filter_bar
      :if={@bar? and @path_fn}
      for={@form}
      id={"#{@id}-filters"}
      count={@count || count(@view)}
      repeats={repeats?(@view)}
      clear={@path_fn.(:clear)}
      path_fn={@path_fn}
      page={@view.page}
      hidden={hidden(@form, @view, @switch_menu?)}
    >
      <:search :if={@view.search?} field={@form["q"]} />
      <:filter
        :for={filter <- @filters}
        field={field(@form, filter)}
        label={filter.label}
        options={filter.options}
        default={filter.default || ""}
        more={filter.more}
        type={filter.type}
      />
    </.filter_bar>

    <div :if={@bar? and !@path_fn} id={"#{@id}-filters"} class="flex flex-wrap gap-4">
      <.input
        :if={@view.search?}
        type="search"
        id={"#{@id}-q"}
        name="report[values][q]"
        value={@view.q}
        label="Search"
        phx-debounce="300"
      />
      <.input
        :for={filter <- @view.filters}
        type="select"
        id={"#{@id}-filter-#{filter.name}"}
        name={"report[values][#{filter.name}]"}
        value={filter.picked}
        label={filter.label}
        options={Enum.map(filter.options, fn {label, value} -> {label, value} end)}
      />
    </div>

    <p :if={!@bar? or !@path_fn} id={"#{@id}-count"} class="hint">{@count || count(@view)}</p>

    {render_slot(@table)}

    <.report_table
      :if={@table == [] and @view.result.rows != []}
      id={"#{@id}-rows"}
      result={@view.result}
      records={@records}
      team={@team}
      now={@now}
      sorts={@view.sorts}
      sort={@view.sort}
      path_fn={@path_fn || (&sort_click/1)}
    />

    <.pagination :if={@view.page && @path_fn} class="my-4" paginated={@view.page} path_fn={@path_fn} />
    """
  end

  @doc "The controls' form: the search, each filter's pick, and the switch and sort it keeps."
  def controls_form(%View{} = view) do
    filters = Map.new(view.filters, &{&1.name, &1.picked})
    switch = if view.switch, do: %{view.switch.name => view.switch.picked}, else: %{}

    %{"q" => view.q, "sort" => view.sort}
    |> Map.merge(filters)
    |> Map.merge(switch)
    |> to_form(as: "values")
  end

  @doc """
  The page's path with `changes` made, `[{name, value}]` or a keyword list, leaving out
  what's at its default; `:clear` takes off the search, the filters, and the switch.
  """
  def path(%View{} = view, base, :clear) do
    controls = ["q", "page" | Enum.map(view.filters, & &1.name)]
    switch = if view.switch, do: [view.switch.name], else: []
    params = Map.drop(view.params, controls ++ switch)
    query(base, params, view.defaults)
  end

  def path(%View{} = view, base, changes) do
    params =
      Enum.reduce(changes, view.params, fn {k, v}, acc -> Map.put(acc, to_string(k), v) end)

    query(base, params, view.defaults)
  end

  defp query(base, params, defaults) do
    params = Map.reject(params, fn {name, value} -> default?(name, value, defaults) end)
    if params == %{}, do: base, else: base <> "?" <> Query.encode(params)
  end

  defp default?(_name, value, _defaults) when value in [nil, ""], do: true
  defp default?("page", value, _defaults), do: to_string(value) == "1"
  defp default?(name, value, defaults), do: Map.get(defaults, name) == to_string(value)

  @doc ~s(How many rows: "7 members" when the first column is a record, "12 rows" otherwise.)
  def count(%View{result: result, total: total}) do
    case result.columns do
      [%{type: {:record, kind}} | _] ->
        Format.count(total, one: "%d #{kind_name(kind)}", many: "%d #{kind_names(kind)}")

      _other ->
        Format.count(total, one: "%d row", many: "%d rows")
    end
  end

  defp kind_name(kind), do: Atom.to_string(kind)

  defp kind_names(:activity), do: "activities"
  defp kind_names(kind), do: kind_name(kind) <> "s"

  defp repeats?(%View{switch: nil}), do: false

  defp repeats?(%View{switch: switch, total: total}),
    do: Enum.any?(switch.tiles, &(&1.value == switch.picked and &1.count == total))

  # The switch rides in the form unless its menu shows it.
  defp hidden(form, view, switch_menu?) do
    switch = if view.switch && !switch_menu?, do: [form[view.switch.name]], else: []
    [form["sort"] | switch]
  end

  # A switch whose pick has no tile, such as All with no All tile, or several picks at
  # once, shows as a menu in the bar, first.
  defp switch_menu(%View{switch: nil}), do: nil

  defp switch_menu(%View{switch: switch}) do
    unless Enum.any?(switch.tiles, &(&1.value == switch.picked)),
      do: %{
        name: switch.name,
        label: switch.label,
        picked: switch.picked,
        default: switch.default,
        more: false,
        options: switch.options
      }
  end

  # A combobox's empty choice is All, so its options leave All out.
  defp menu(filter, combobox) do
    if filter.name in combobox,
      do:
        Map.merge(filter, %{type: "combobox", options: List.keydelete(filter.options, "all", 1)}),
      else: Map.put(filter, :type, "select")
  end

  defp field(form, %{type: "combobox"} = filter) do
    field = form[filter.name]
    if field.value == "all", do: %{field | value: ""}, else: field
  end

  defp field(form, filter), do: form[filter.name]

  # In the editor, a pick is an event the form takes.
  defp pick(name, value), do: JS.push("pick", value: %{name: name, value: value})

  defp sort_click(changes), do: pick("sort", Keyword.fetch!(changes, :sort))
end
