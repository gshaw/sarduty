defmodule Web.Components.ReportTable do
  @moduledoc """
  A report's rows (#768), each cell the standard column for its type: a member, an
  activity, an item, a qualification, and a group link to their pages; a date, hours, and
  numbers through Service.Format. A report with `totals` ends in a Total row.
  """
  use Web, :function_component

  import Web.Components.Columns
  import Web.Components.Table

  alias App.Report.Runner
  alias App.Report.Value
  alias Service.Format

  attr :id, :string, required: true
  attr :result, App.Report.Result, required: true
  attr :records, :map, required: true, doc: "from App.ViewData.ReportRecords.load/3"
  attr :team, :any, required: true
  attr :now, :any, required: true

  def report_table(assigns) do
    assigns =
      assign(assigns,
        rows: rows(assigns.result),
        columns: Enum.with_index(assigns.result.columns)
      )

    ~H"""
    <.table id={@id} rows={@rows} row_id={&"#{@id}-#{&1.key}"} class="table-striped">
      <:col
        :let={row}
        :for={{column, i} <- @columns}
        label={label(column, @records)}
        align={align(column)}
      >
        <.report_cell
          value={Enum.at(row.cells, i)}
          column={column}
          total={row.total}
          first={i == 0}
          records={@records}
          team={@team}
          now={@now}
        />
      </:col>
    </.table>
    """
  end

  defp rows(result) do
    rows =
      result.rows
      |> Enum.with_index()
      |> Enum.map(fn {cells, i} -> %{key: i, cells: cells, total: false} end)

    if result.totals,
      do: Enum.concat(rows, [%{key: "total", cells: result.totals, total: true}]),
      else: rows
  end

  @doc "A column's heading: its label, or the name of the record a pivot column is for."
  def label(%{label: nil, pivot_type: {:record, kind}, pivot: id}, records),
    do: records |> Map.get(kind, %{}) |> Map.get(id) |> record_text()

  def label(%{label: label}, _records), do: label

  defp record_text(nil), do: ""
  defp record_text(%{name: name}), do: name
  defp record_text(%{title: title}), do: title

  defp align(%{type: type}) when type in [:number, :hours, :km], do: "right"
  defp align(_column), do: nil

  attr :value, :any, required: true
  attr :column, :map, required: true
  attr :total, :boolean, required: true
  attr :first, :boolean, required: true
  attr :records, :map, required: true
  attr :team, :any, required: true
  attr :now, :any, required: true

  defp report_cell(%{total: true, first: true, value: nil} = assigns),
    do: ~H"<strong>Total</strong>"

  defp report_cell(%{total: true} = assigns),
    do: ~H"<strong>{value_text(@value, @column, @team)}</strong>"

  defp report_cell(%{value: nil} = assigns), do: ~H""

  defp report_cell(%{column: %{type: {:record, kind}}} = assigns) do
    assigns = assign(assigns, kind: kind, record: get_in(assigns.records, [kind, assigns.value]))

    ~H"""
    <.record_cell
      :if={@record}
      kind={@kind}
      record={@record}
      records={@records}
      team={@team}
      now={@now}
    />
    """
  end

  defp report_cell(%{column: %{type: :date}} = assigns),
    do: ~H"<.date_cell value={@value} timezone={@team.timezone} />"

  defp report_cell(%{column: %{type: :hours}} = assigns), do: ~H"<.hours_cell minutes={@value} />"
  defp report_cell(assigns), do: ~H"{value_text(@value, @column, @team)}"

  attr :kind, :atom, required: true
  attr :record, :map, required: true
  attr :records, :map, required: true
  attr :team, :any, required: true
  attr :now, :any, required: true

  defp record_cell(%{kind: :member} = assigns),
    do:
      ~H"<.member_cell member={@record} team={@team} standing={@records.standings[@record.id]} />"

  defp record_cell(%{kind: :activity} = assigns),
    do: ~H"<.activity_cell activity={@record} team={@team} now={@now} />"

  defp record_cell(%{kind: :item} = assigns), do: ~H"<.item_cell item={@record} team={@team} />"

  defp record_cell(%{kind: :qualification} = assigns),
    do: ~H"<.qualification_cell qualification={@record} team={@team} />"

  defp record_cell(%{kind: :group} = assigns),
    do: ~H"<.group_cell group={@record} team={@team} />"

  attr :value, Value, required: true
  attr :id, :string, required: true
  attr :name, :string, required: true, doc: ~s(the form's name for it, such as "values[year]")

  @doc """
  A value picked when the report runs (App.Report.Value): a menu for a year or a choice,
  a date box for a date, and a text box for the rest.
  """
  def report_value(%{value: %Value{kind: kind}} = assigns) when kind in [:year, :choice] do
    ~H"""
    <.input
      type={if length(@value.choices) > 12, do: "combobox", else: "select"}
      id={@id}
      name={@name}
      value={Value.param(@value)}
      label={@value.label}
      options={@value.choices}
    />
    """
  end

  def report_value(%{value: %Value{kind: :date}} = assigns) do
    ~H"""
    <.input type="date" id={@id} name={@name} value={Value.param(@value)} label={@value.label} />
    """
  end

  def report_value(assigns) do
    ~H"""
    <.input
      type="text"
      id={@id}
      name={@name}
      value={Value.param(@value)}
      label={@value.label}
      phx-debounce="400"
    />
    """
  end

  @doc "A value as text, as a cell shows it."
  def value_text(nil, _column, _team), do: ""
  def value_text(value, %{type: :hours}, _team), do: Format.duration(value)
  def value_text(value, %{type: :km}, _team), do: Format.km(value)
  def value_text(value, %{type: :number}, _team), do: Format.number(value)
  def value_text(value, %{type: :date}, team), do: Format.date_short(value, team.timezone)
  def value_text(true, %{type: :bool}, _team), do: "Yes"
  def value_text(false, %{type: :bool}, _team), do: "No"
  def value_text(value, %{type: :list}, _team), do: Enum.join(value, ", ")

  def value_text(value, %{type: :choice, choices: choices}, _team),
    do: Runner.choice_label(choices || [], value)

  def value_text(value, %{type: :month}, _team), do: Runner.month_name(value)
  def value_text(value, %{type: :quarter}, _team), do: "Q#{value}"
  def value_text(value, _column, _team), do: to_string(value)
end
