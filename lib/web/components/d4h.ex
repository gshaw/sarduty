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

  # D4H's own tags on an activity: data, not status, so outlined. The primary and secondary
  # hours tags aren't shown here; activity_hours_type/1 puts them beside the hours.
  def activity_tags(assigns) do
    assigns = assign(assigns, :tags, other_tags(assigns.activity.tags))

    ~H"""
    <div :if={@tags != []} {@rest}>
      <span class="badges">
        <.badge :for={tag <- @tags} kind={:outline}>{tag}</.badge>
      </span>
    </div>
    """
  end

  defp other_tags(tags) do
    (tags -- [Activity.primary_hours_tag(), Activity.secondary_hours_tag()]) |> Enum.sort()
  end

  @doc "Which SARVAC hours an activity counts for, from its D4H tags: Primary, Secondary, or nil."
  def activity_hours_type(activity) do
    cond do
      Activity.primary_hours_tag() in activity.tags -> "Primary"
      Activity.secondary_hours_tag() in activity.tags -> "Secondary"
      true -> nil
    end
  end

  attr :activity, :map, required: true

  # The kind on its own, as on an activity's page: a solid tag in D4H's colour, "Draft" when
  # it isn't published, and the tracking number as text.
  def activity_badges(assigns) do
    ~H"""
    <span class="badges">
      <.badge kind={activity_kind_badge(@activity.activity_kind)} title="Activity kind">
        {String.capitalize(@activity.activity_kind)}
      </.badge>
      <.badge :if={!@activity.is_published}>Draft</.badge>
      <.badge :if={@activity.deleted_at} kind={:danger}>Deleted in D4H</.badge>
    </span>
    <span :if={@activity.tracking_number} class="mono ml-1" title="Tracking number">
      {@activity.tracking_number}
    </span>
    """
  end

  attr :activity, :map, required: true

  # The kind in a table column, where every row has one: a marker in D4H's colour.
  def activity_kind(assigns) do
    ~H"""
    <span class={["activity-kind", "activity-kind-#{@activity.activity_kind}"]}>
      {String.capitalize(@activity.activity_kind)}
    </span>
    <div :if={!@activity.is_published}>
      <.badge>Draft</.badge>
    </div>
    <div :if={@activity.tracking_number} class="mono text-secondary-1">
      {@activity.tracking_number}
    </div>
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
      class="bg-base-0 size-48 rounded"
      src={~p"/teams/#{@member.team}/members/#{@member.id}/image"}
    />
    """
  end
end
