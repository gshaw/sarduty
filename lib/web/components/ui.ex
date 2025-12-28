defmodule Web.Components.UI do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component

  use Gettext, backend: Web.Gettext

  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :trailing

  def form_actions(assigns) do
    ~H"""
    <div class={["form-actions flex flex-wrap", @class]}>
      <div class="flex gap-hspacer grow">
        {render_slot(@inner_block)}
      </div>
      <%= if @trailing do %>
        <div class="flex gap-hspacer">
          {render_slot(@trailing)}
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  attr :class, :string, default: nil
  attr :size, :string, default: "6"
  slot :inner_block

  def spinner(assigns) do
    ~H"""
    <span class={["inline-flex items-center", @class]}>
      <span class="mr-2">
        <Web.Components.Core.icon
          name="hero-arrow-path"
          class={"motion-safe:animate-spin size=#{@size}"}
        />
      </span>
      <span :if={@inner_block}>{render_slot(@inner_block)}</span>
    </span>
    """
  end

  slot :inner_block, required: true

  def hint(assigns) do
    ~H"""
    <div class="block my-1 font-normal text-sm text-secondary-1">
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block mb-1 label">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <div class="my-1 font-normal text-sm text-danger-1 phx-no-feedback:hidden">
      {render_slot(@inner_block)}
    </div>
    """
  end
end
