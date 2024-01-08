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
    <table class={["table", @class]}>
      <thead>
        <tr :if={@header_row != []} class="table-header-row">
          <%= render_slot(@header_row) %>
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
            class={[
              Map.get(col, :class),
              if(Map.get(col, :align) == "right", do: "md:text-right", else: nil)
            ]}
          >
            <%= render_slot(col, @row_item.(row)) %>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  def table_header(assigns) do
    ~H"""
    <th class={[@class, if(@align == "right", do: "md:text-right", else: nil)]}>
      <%= if @sorts == nil do %>
        <%= @label %>
      <% else %>
        <%= case Enum.find(@sorts, fn {_k, v} -> v == @sort end) do %>
          <% nil -> %>
            <% {suffix, sort} = List.first(@sorts) %>
            <.a kind={:custom} class="w-full inline-block" navigate={@path_fn.(page: 1, sort: sort)}>
              <.sort_header_content
                label={@label}
                suffix={if Enum.count(@sorts) == 1, do: suffix, else: "⇅"}
                suffix_class="text-disabled"
                align={@align}
              />
            </.a>
          <% {suffix, current_sort} -> %>
            <%= if Enum.count(@sorts) == 1 do %>
              <.sort_header_content label={@label} suffix={suffix} align={@align} />
            <% else %>
              <% sort = find_next_sort(@sorts, current_sort) %>
              <.a kind={:custom} class="w-full inline-block" navigate={@path_fn.(page: 1, sort: sort)}>
                <.sort_header_content label={@label} suffix={suffix} align={@align} />
              </.a>
            <% end %>
        <% end %>
      <% end %>
    </th>
    """
  end

  attr :label, :string, required: true
  attr :suffix, :string, required: true
  attr :suffix_class, :string, default: nil
  attr :align, :string, values: ["left", "right"]

  defp sort_header_content(assigns) do
    ~H"""
    <%= if @align == "right" do %>
      <span class={@suffix_class}><%= @suffix %></span><%= StringHelpers.no_break_space() %><%= @label %>
    <% else %>
      <%= @label %><%= StringHelpers.no_break_space() %><span class={@suffix_class}><%= @suffix %></span>
    <% end %>
    """
  end

  defp find_next_sort([{_label, sort}] = _sorts, _current_sort), do: sort

  defp find_next_sort([{_label1, sort1}, {_label2, sort2}] = _sorts, current_sort) do
    if current_sort == sort1, do: sort2, else: sort1
  end
end
