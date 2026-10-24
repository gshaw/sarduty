defmodule Web.Components.Standing do
  @moduledoc "A member's standing (#366) as people read it."
  use Web, :function_component

  alias App.Model.MemberAwayPeriod

  @doc ~s{The standing as text: "Active", "Away until March 1, 2027 (Parental leave)", "Not a person", or "Retired".}
  defdelegate text(standing), to: MemberAwayPeriod, as: :describe_standing

  attr :id, :string, default: nil
  attr :standing, :any, required: true, doc: "from MemberAwayPeriod.standing_today/3"
  attr :item_count, :integer, default: 0, doc: "the items the member holds"

  @doc """
  The standing as a badge beside a member's name, or nothing when they are active. Away
  ends, so it is a warning; Retired and Not a person are settled. Retired with items still
  to come back is a warning too, and counts them (#490).
  """
  def standing_badge(%{standing: :active} = assigns), do: ~H""

  def standing_badge(%{standing: :retired, item_count: count} = assigns) when count > 0 do
    ~H"""
    <.badge id={@id} kind={:warning}>
      {Service.Format.count(@item_count, one: "Retired with %d item", many: "Retired with %d items")}
    </.badge>
    """
  end

  def standing_badge(assigns) do
    assigns = assign(assigns, kind: badge_kind(assigns.standing))

    ~H"""
    <.badge id={@id} kind={@kind}>{badge_text(@standing)}</.badge>
    """
  end

  defp badge_kind({:away, _period}), do: :warning
  defp badge_kind(_settled), do: :default

  @doc ~s{The badge's words: "Away until Mar 1, 2027", "Retired", or "Not a person". The reason stays on the Standing tab.}
  def badge_text({:away, period}), do: "Away until #{Service.Format.date_short(period.ends_on)}"
  def badge_text(standing), do: text(standing)
end
