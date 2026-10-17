defmodule Web.Components.ViewSwitch do
  @moduledoc """
  Links that switch a list between a few views, with a count each (#350). See
  /styles/view-switch.
  """
  use Phoenix.Component

  @doc """
  Renders a row of joined links, one per view, the current one filled.

  ## Examples

      <.view_switch label="Awards">
        <:view patch={~p"/…"} current={@view == :active} count={131}>Active</:view>
        <:view patch={~p"/…?view=expired"} current={@view == :expired} count={40}>Expired</:view>
      </.view_switch>
  """
  attr :label, :string, required: true, doc: "what the views choose between, for screen readers"
  attr :id, :string, default: nil

  slot :view, required: true do
    attr :patch, :string, required: true
    attr :current, :boolean
    attr :count, :integer
    attr :id, :string
  end

  def view_switch(assigns) do
    ~H"""
    <nav id={@id} class="view-switch" aria-label={@label}>
      <.link
        :for={view <- @view}
        id={view[:id]}
        patch={view.patch}
        aria-current={view[:current] && "page"}
      >
        {render_slot(view)}
        <span :if={view[:count]} class="view-switch-count">
          {Service.Format.number(view.count)}
        </span>
      </.link>
    </nav>
    """
  end
end
