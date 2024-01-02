defmodule Web.Components.D4H do
  use Web, :function_component

  attr :activity, :map, required: true

  def activity_title(assigns) do
    ~H"""
    <span>#<%= @activity.ref_id %> <%= @activity.title %></span>
    """
  end

  attr :activity, :map, required: true
  attr :rest, :global, include: ~w(class)

  def activity_tags(assigns) do
    ~H"""
    <div {@rest}>
      <%= for tag <- @activity.tags do %>
        <span class="badge"><%= tag %></span>
      <% end %>
    </div>
    """
  end

  attr :activity, :map, required: true

  def activity_kind_badge(assigns) do
    ~H"""
    <span title="Activity kind" class="badge"><%= @activity.activity_kind %></span>
    """
  end

  attr :activity, :map, required: true

  def activity_badges(assigns) do
    ~H"""
    <.activity_kind_badge activity={@activity} />
    <.activity_tracking_number_badge activity={@activity} />
    """
  end

  attr :activity, :map, required: true

  def activity_tracking_number_badge(assigns) do
    ~H"""
    <span
      :if={@activity.tracking_number}
      title="Tracking number"
      class="badge badge-warning"
      phx-no-format
    ><%= @activity.tracking_number %></span>
    """
  end
end
