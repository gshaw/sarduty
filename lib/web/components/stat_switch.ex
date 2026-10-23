defmodule Web.Components.StatSwitch do
  @moduledoc """
  A list's split as counts, each a link that filters the list. See /styles/stat-switch.
  """
  use Phoenix.Component

  @doc """
  Renders a row of counts over a list, each on a grey tile with what it counts, the current one
  light blue with a primary bar. All comes first. A view's `marker` puts a coloured square before its label,
  as the rows show it: `marker="incident"` is `.marker-incident`. An `icon` puts an icon
  there instead, such as `icon="hero-clock-micro"`.

  ## Examples

      <.stat_switch label="Members">
        <:view patch={~p"/…?view=all"} current={@view == :all} count={171}>All</:view>
        <:view patch={~p"/…"} current={@view == :active} count={131}>Active</:view>
        <:view patch={~p"/…?view=expired"} current={@view == :expired} count={40}>Expired</:view>
      </.stat_switch>
  """
  attr :label, :string, required: true, doc: "what the counts split, for screen readers"
  attr :id, :string, default: nil

  slot :view, required: true do
    attr :patch, :string, required: true
    attr :current, :boolean
    attr :count, :integer, required: true
    attr :marker, :string
    attr :icon, :string, doc: "an icon before the label, as the rows show it"
    attr :id, :string
  end

  def stat_switch(assigns) do
    ~H"""
    <nav id={@id} class="stat-switch" aria-label={@label}>
      <.link
        :for={view <- @view}
        id={view[:id]}
        patch={view.patch}
        aria-current={view[:current] && "page"}
        class={view.count == 0 && "is-zero"}
      >
        <span class="stat-switch-value">{Service.Format.number(view.count)}</span>
        <span class="stat-switch-label">
          <span :if={view[:marker]} class={["marker", "marker-#{view.marker}"]}>
            {render_slot(view)}
          </span>
          <span :if={view[:icon]} class="icon-label">
            <span class={view.icon} aria-hidden="true" />{render_slot(view)}
          </span>
          <span :if={!view[:marker] && !view[:icon]}>{render_slot(view)}</span>
        </span>
      </.link>
    </nav>
    """
  end
end
