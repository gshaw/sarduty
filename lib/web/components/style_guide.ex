defmodule Web.Components.StyleGuide do
  use Web, :function_component

  import Web.Components.A

  attr :current, :atom, required: true, values: [:index, :tables, :forms]

  def style_guide_header(assigns) do
    ~H"""
    <header class="mb-8">
      <h1 class="title">Style Guide</h1>
      <div class="mt-p">
        <nav class="tabs" aria-label="Style guide pages">
          <.tab navigate={~p"/styles"} current={@current == :index}>Overview</.tab>
          <.tab navigate={~p"/styles/tables"} current={@current == :tables}>Tables</.tab>
          <.tab navigate={~p"/styles/forms"} current={@current == :forms}>Forms</.tab>
        </nav>
      </div>
    </header>
    """
  end

  attr :navigate, :string, required: true
  attr :current, :boolean, required: true
  slot :inner_block, required: true

  defp tab(assigns) do
    ~H"""
    <.a kind={:custom} navigate={@navigate} aria-current={@current && "page"}>
      {render_slot(@inner_block)}
    </.a>
    """
  end

  attr :class, :string, default: nil
  attr :title, :string, required: true
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def style_group(assigns) do
    ~H"""
    <section id={@id} class={["shadow p-4 space-y-4 mb-8 rounded", @class]}>
      <h2 class="heading">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :fg, :string, required: true
  attr :bg, :string, required: true

  def color_swatch(assigns) do
    ~H"""
    <div class={[
      "px-8 py-5 m-1 text-center inline-block align-middle rounded text-xs",
      @bg,
      @fg
    ]}>
      {@bg}
    </div>
    """
  end
end
