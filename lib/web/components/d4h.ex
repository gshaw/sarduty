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

  def activity_badges(assigns) do
    ~H"""
    <span title="Activity kind" class={"badge badge-#{@activity.activity_kind}"}>
      <%= @activity.activity_kind %>
    </span>
    <span :if={@activity.tracking_number} title="Tracking number" class="badge">
      <%= @activity.tracking_number %>
    </span>
    <span :if={@activity.is_published} class="badge">published</span>
    """
  end

  attr :member, :map, required: true

  def member_image(assigns) do
    ~H"""
    <img
      class="bg-base-0 aspect-square object-cover size-48 rounded"
      src={~p"/#{@member.team.subdomain}/members/#{@member.id}/image"}
    />
    """
  end
end
