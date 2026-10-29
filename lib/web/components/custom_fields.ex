defmodule Web.Components.CustomFields do
  use Phoenix.Component

  import Web.Components.Core

  # A record's D4H custom fields (#681), from App.Model.CustomField.rows/4: a table on the
  # record's Fields tab, or a detail list under a heading on a page with no tabs, such as
  # Your membership's Contact details. A required field with no value says Missing. The
  # style guide's Detail list page shows both.

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :class, :string, default: "mt-8"

  @doc "The rows as a detail list under a heading, or nothing when there are none."
  def custom_fields(assigns) do
    ~H"""
    <section :if={@rows != []} id={@id} class={@class}>
      <h2 class="heading">{@title}</h2>
      <dl class="measure">
        <div :for={row <- @rows} id={"#{@id}-#{row.field.d4h_custom_field_id}"}>
          <dt>{row.field.title}</dt>
          <dd :if={!row.missing?}>{row.text}</dd>
          <dd :if={row.missing?}>
            <.badge kind={:warning}>Missing</.badge>
          </dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true

  attr :required, :integer,
    default: 0,
    doc: "how many of the fields D4H needs to publish, for the count over the missing ones"

  @doc """
  A record's Fields tab: a table of each field and its value. The missing ones come
  first, under a count, then the rest in D4H's order.
  """
  def custom_fields_table(assigns) do
    {missing, filled} = Enum.split_with(assigns.rows, & &1.missing?)
    assigns = assign(assigns, missing: missing, filled: filled)

    ~H"""
    <section id={@id}>
      <div :if={@missing != []} class="mb-8">
        <p id={"#{@id}-missing-count"} class="mb-4">
          {Service.Format.count(length(@missing),
            one: "%d of #{@required} needed to publish is empty.",
            many: "%d of #{@required} needed to publish are empty."
          )}
        </p>
        <.fields_table id={"#{@id}-missing"} prefix={@id} rows={@missing} />
      </div>
      <.fields_table :if={@filled != []} id={"#{@id}-filled"} prefix={@id} rows={@filled} />
      <p :if={@rows == []} class="hint">No fields filled in.</p>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :prefix, :string, required: true, doc: "each row's id starts with it"
  attr :rows, :list, required: true

  defp fields_table(assigns) do
    ~H"""
    <div class="table-wrap">
      <table id={@id} class="table table-striped table-fields">
        <tbody>
          <tr :for={row <- @rows} id={"#{@prefix}-#{row.field.d4h_custom_field_id}"}>
            <th scope="row">{row.field.title}</th>
            <td :if={!row.missing?}>{row.text}</td>
            <td :if={row.missing?}>
              <.badge kind={:warning}>Missing</.badge>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
