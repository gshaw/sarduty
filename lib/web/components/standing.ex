defmodule Web.Components.Standing do
  @moduledoc "A member's standing (#366) as people read it."
  use Web, :function_component

  @doc ~s{The standing as text: "Active", "Away until March 1, 2027 (Parental leave)", "Retiring", "Not a person", or "Retired".}
  defdelegate text(standing), to: App.Model.Standing

  attr :id, :string, default: nil
  attr :standing, :any, required: true, doc: "from App.Model.Standing.today/3"
  attr :follows, :boolean, default: false, doc: "after the name on the same line"

  @doc """
  The standing as a badge beside a member's name, or nothing when they are active. Away
  ends and Retiring leads to Retired, so both are warnings; Retired and Not a person are
  settled.
  """
  def standing_badge(%{standing: :active} = assigns), do: ~H""

  def standing_badge(assigns) do
    assigns = assign(assigns, kind: badge_kind(assigns.standing))

    ~H"""
    <.badge id={@id} kind={@kind} follows={@follows}>{badge_text(@standing)}</.badge>
    """
  end

  defp badge_kind({:away, _period}), do: :warning
  defp badge_kind(:retiring), do: :warning
  defp badge_kind(_settled), do: :default

  @doc ~s{The badge's words: "Away until Mar 1, 2027", "Retiring", "Retired", or "Not a person". The reason stays on the Standing tab.}
  def badge_text({:away, period}), do: "Away until #{Service.Format.date_short(period.ends_on)}"
  def badge_text(standing), do: text(standing)
end
