defmodule SartaskWeb.WebComponents.FormActions do
  use SartaskWeb, :function_component

  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :trailing

  def form_actions(assigns) do
    ~H"""
    <div class={["form-actions flex flex-wrap", @class]}>
      <div class="flex-grow">
        <%= render_slot(@inner_block) %>
      </div>
      <%= if @trailing do %>
        <div>
          <%= render_slot(@trailing) %>
        </div>
      <% end %>
    </div>
    """
  end
end
