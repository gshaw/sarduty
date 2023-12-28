defmodule Web.Components.Table do
  use Phoenix.Component

  import Web.Components.A

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

  slot :header_row, defualt: nil

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class={["table", @class]}>
      <thead>
        <tr :if={@header_row} class="table-header-row">
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
              if(Map.get(col, :align) == "right", do: "text-right", else: nil)
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
    <th class={[@class, if(@align == "right", do: "text-right", else: nil)]}>
      <%= if @sorts == nil do %>
        <%= @label %>
      <% else %>
        <%= case Enum.find(@sorts, fn {_k, v} -> v == @sort end) do %>
          <% nil -> %>
            <% {_suffix, sort} = List.first(@sorts) %>
            <.a kind={:custom} class="w-full inline-block" navigate={@path_fn.(page: 1, sort: sort)}>
              <%= @label %>
            </.a>
          <% {suffix, current_sort} -> %>
            <%= if Enum.count(@sorts) == 1 do %>
              <%= if @align == "right" do %>
                <%= suffix %><%= Service.StringHelpers.no_break_space() %><%= @label %>
              <% else %>
                <%= @label %><%= Service.StringHelpers.no_break_space() %><%= suffix %>
              <% end %>
            <% else %>
              <% sort = find_next_sort(@sorts, current_sort) %>
              <.a kind={:custom} class="w-full inline-block" navigate={@path_fn.(page: 1, sort: sort)}>
                <%= if @align == "right" do %>
                  <%= suffix %><%= Service.StringHelpers.no_break_space() %><%= @label %>
                <% else %>
                  <%= @label %><%= Service.StringHelpers.no_break_space() %><%= suffix %>
                <% end %>
              </.a>
            <% end %>
        <% end %>
      <% end %>
    </th>
    """
  end

  defp find_next_sort([{_label, sort}] = _sorts, _current_sort), do: sort

  defp find_next_sort([{_label1, sort1}, {_label2, sort2}] = _sorts, current_sort) do
    if current_sort == sort1, do: sort2, else: sort1
  end
end
