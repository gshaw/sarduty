defmodule Web.Components.D4H do
  use Web, :function_component

  alias App.Model.Activity

  attr :activity, :map, required: true

  def activity_title(assigns) do
    ~H"""
    <span>{@activity.ref_id}: {@activity.title}</span>
    """
  end

  attr :activity, :map, required: true
  attr :rest, :global, include: ~w(class)

  def activity_tags(assigns) do
    assigns
    |> Phoenix.Component.assign(:sorted_tags, sort_tags(assigns.activity.tags))
    |> then(fn assigns ->
      ~H"""
      <div {@rest}>
        <%= for tag <- @sorted_tags do %>
          <span class="badge">
            <%= if tag in [Activity.primary_hours_tag(), Activity.secondary_hours_tag()] do %>
              <strong>{tag}</strong>
            <% else %>
              {tag}
            <% end %>
          </span>
        <% end %>
      </div>
      """
    end)
  end

  defp sort_tags(tags) do
    primary_tag = Activity.primary_hours_tag()
    secondary_tag = Activity.secondary_hours_tag()

    {priority_tags, other_tags} =
      Enum.split_with(tags, fn tag -> tag in [primary_tag, secondary_tag] end)

    primary = Enum.filter(priority_tags, fn tag -> tag == primary_tag end)
    secondary = Enum.filter(priority_tags, fn tag -> tag == secondary_tag end)
    sorted_others = Enum.sort(other_tags)

    primary ++ secondary ++ sorted_others
  end

  attr :activity, :map, required: true

  def activity_badges(assigns) do
    ~H"""
    <span title="Activity kind" class={["badge", "badge-#{@activity.activity_kind}"]}>
      {String.capitalize(@activity.activity_kind)}
    </span>
    <span :if={@activity.tracking_number} title="Tracking number" class="badge">
      {@activity.tracking_number}
    </span>
    <span :if={@activity.is_published} class="badge">Published</span>
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
