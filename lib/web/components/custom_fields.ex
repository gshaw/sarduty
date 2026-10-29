defmodule Web.Components.CustomFields do
  use Phoenix.Component

  import Web.Components.Core

  # A record's D4H custom fields (#681), from App.Model.CustomField.rows/4, as a detail
  # list: under a heading, or as pairs inside a sidebar's own list. A required field
  # with no value says Missing. The style guide's Detail list page shows it.

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :class, :string, default: "mt-8"

  @doc "The rows under a heading, or nothing when there are none."
  def custom_fields(assigns) do
    ~H"""
    <section :if={@rows != []} id={@id} class={@class}>
      <h2 class="heading">{@title}</h2>
      <dl class="measure">
        <.custom_field_pairs id={@id} rows={@rows} />
      </dl>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true

  @doc "The rows as `dt` and `dd` pairs, for inside a `<dl>`."
  def custom_field_pairs(assigns) do
    ~H"""
    <div :for={row <- @rows} id={"#{@id}-#{row.field.d4h_custom_field_id}"}>
      <dt>{row.field.title}</dt>
      <dd :if={!row.missing?}>{row.text}</dd>
      <dd :if={row.missing?}>
        <.badge kind={:warning}>Missing</.badge>
      </dd>
    </div>
    """
  end
end
