defmodule Web.Components.Table do
  use Phoenix.Component

  import Web.Components.A

  alias Service.StringHelpers

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  attr :class, :string, default: nil
  attr :sort, :string, default: nil
  attr :path_fn, :any, default: nil

  slot :col, required: true do
    attr :label, :string
    attr :class, :string
    attr :align, :string, values: ["left", "right"]
    attr :sorts, :list
  end

  slot :header_row

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="table-wrap">
      <table class={["table", @class]}>
        <thead>
          <tr :if={@header_row != []} class="table-header-row">
            {render_slot(@header_row)}
          </tr>
          <tr>
            <.table_header
              :for={col <- @col}
              label={col[:label]}
              class={col[:class]}
              align={col[:align]}
              sorts={col[:sorts]}
              sort={@sort}
              path_fn={@path_fn}
            />
          </tr>
        </thead>
        <tbody id={@id}>
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
            <td
              :for={col <- @col}
              data-label={col[:label]}
              class={[
                Map.get(col, :class),
                if(Map.get(col, :align) == "right", do: "text-right", else: nil)
              ]}
            >
              {render_slot(col, @row_item.(row))}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :label, :string, default: nil
  attr :class, :string, default: nil
  attr :align, :string, default: nil, values: [nil, "left", "right"]

  attr :sorts, :list,
    default: nil,
    doc: ~s(the column's {suffix, sort} pairs, such as [{"↓", "date-"}, {"↑", "date"}])

  attr :sort, :string, default: nil, doc: "the sort the table has now"
  attr :path_fn, :any, default: nil

  def table_header(%{sorts: nil} = assigns) do
    ~H"""
    <th class={[@class, @align == "right" && "text-right"]}>{@label}</th>
    """
  end

  def table_header(assigns) do
    assigns = assign(assigns, :header, sort_header(assigns.sorts, assigns.sort))

    ~H"""
    <th class={[@class, @align == "right" && "text-right"]} aria-sort={@header.aria_sort}>
      <.a
        :if={@header.link?}
        kind={:custom}
        class="w-full inline-block"
        navigate={@path_fn.(page: 1, sort: @header.next_sort)}
      >
        <.sort_header_content label={@label} header={@header} align={@align} />
      </.a>
      <.sort_header_content :if={!@header.link?} label={@label} header={@header} align={@align} />
    </th>
    """
  end

  @doc """
  Works out a sortable column header from its `{suffix, sort}` pairs and the table's sort.

  A column the table isn't sorted by links to its first sort, with a faded suffix: its
  arrow, or ⇅ when it sorts both ways. The sorted column shows its arrow, sets `aria-sort`,
  and links to its other sort, or isn't a link when it sorts one way only.
  """
  def sort_header(sorts, sort) do
    case List.keyfind(sorts, sort, 1) do
      nil ->
        [{suffix, first_sort} | _] = sorts
        suffix = if length(sorts) == 1, do: suffix, else: "⇅"
        %{suffix: suffix, current?: false, link?: true, next_sort: first_sort, aria_sort: nil}

      {suffix, _sort} ->
        next_sort = next_sort(sorts, sort)

        %{
          suffix: suffix,
          current?: true,
          link?: next_sort != nil,
          next_sort: next_sort,
          aria_sort: aria_sort(suffix)
        }
    end
  end

  defp next_sort([_only], _sort), do: nil
  defp next_sort([{_, sort}, {_, other}], sort), do: other
  defp next_sort([{_, other}, _], _sort), do: other

  defp aria_sort("↑"), do: "ascending"
  defp aria_sort("↓"), do: "descending"

  attr :label, :string, required: true
  attr :header, :map, required: true
  attr :align, :string, default: nil

  defp sort_header_content(assigns) do
    ~H"""
    <%= if @align == "right" do %>
      <span class={["sort-suffix", @header.current? && "is-current"]}>{@header.suffix}</span>{StringHelpers.no_break_space()}{@label}
    <% else %>
      {@label}{StringHelpers.no_break_space()}<span class={[
        "sort-suffix",
        @header.current? && "is-current"
      ]}>{@header.suffix}</span>
    <% end %>
    """
  end
end
