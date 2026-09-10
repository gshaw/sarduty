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
        <.badge :for={tag <- @sorted_tags}>
          <%= if tag in [Activity.primary_hours_tag(), Activity.secondary_hours_tag()] do %>
            <strong>{tag}</strong>
          <% else %>
            {tag}
          <% end %>
        </.badge>
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
    <.badge kind={activity_kind_badge(@activity.activity_kind)} title="Activity kind">
      {String.capitalize(@activity.activity_kind)}
    </.badge>
    <.badge :if={@activity.tracking_number} title="Tracking number">
      {@activity.tracking_number}
    </.badge>
    <.badge :if={!@activity.is_published}>Draft</.badge>
    <.badge :if={@activity.is_published}>Published</.badge>
    """
  end

  # activity_kind is a D4H value; anything unexpected gets the plain badge
  defp activity_kind_badge("incident"), do: :incident
  defp activity_kind_badge("exercise"), do: :exercise
  defp activity_kind_badge("event"), do: :event
  defp activity_kind_badge(_kind), do: :default

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
