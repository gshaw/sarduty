defmodule Web.Components.Verify do
  @moduledoc "The result blocks shared by the verify site's pages for ID cards and letters."
  use Web, :function_component

  attr :kind, :atom, required: true, values: [:ok, :warn, :bad]
  attr :title, :string, required: true
  slot :inner_block, required: true

  def band(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 p-4 rounded-lg",
      @kind == :ok && "bg-(--success) text-(--on-fill)",
      @kind == :warn && "bg-(--warning) text-(--on-warning)",
      @kind == :bad && "bg-(--danger) text-(--on-fill)"
    ]}>
      <.icon name={band_icon(@kind)} class="size-8 shrink-0" />
      <div>
        <div class="text-xl font-semibold">{@title}</div>
        <div class="text-sm">{render_slot(@inner_block)}</div>
      </div>
    </div>
    """
  end

  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <div class="mt-4 p-4 rounded-lg border border-hr bg-base-0">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def fact(assigns) do
    ~H"""
    <div class={@class}>
      <div class="text-xs font-medium uppercase tracking-wide text-secondary-1">{@label}</div>
      <div class="text-lg font-semibold text-base-content">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp band_icon(:ok), do: "hero-check-circle"
  defp band_icon(:warn), do: "hero-exclamation-triangle"
  defp band_icon(:bad), do: "hero-x-circle"
end
