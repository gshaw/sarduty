defmodule Web.Components.GroupRule do
  @moduledoc """
  The group rule editor on a group's page: a table of the endorsements the rule
  requires, each with a Remove button, and a menu to add another. The style guide's
  Build a group rule pattern renders it with made-up endorsements.

  It takes plain maps, so the guide needs no database: each row is
  `%{id, name, path, qualifications}`, with `qualifications` as text, and `options` are
  `{name, id}` for the team's endorsements the rule doesn't have yet.
  """
  use Phoenix.Component

  import Web.Components.A, only: [a: 1]
  import Web.Components.Core, only: [button: 1]
  import Web.Components.Table, only: [table: 1]

  attr :rows, :list, required: true
  attr :options, :list, required: true
  attr :new_path, :string, required: true

  def rule_editor(assigns) do
    ~H"""
    <p class="text-text-muted">
      Members must hold every endorsement here to be in this group.
    </p>

    <.table :if={@rows != []} id="rule-endorsements" rows={@rows} row_id={&"rule-#{&1.id}"}>
      <:col :let={row} label="Endorsement">
        <.a navigate={row.path}>{row.name}</.a>
      </:col>
      <:col :let={row} label="Earned by any of">{row.qualifications}</:col>
      <:col :let={row} label="" align="right">
        <.button size={:sm} phx-click="remove-endorsement" phx-value-endorsement-id={row.id}>
          Remove
        </.button>
      </:col>
    </.table>

    <form
      id="add-endorsement-form"
      phx-submit="add-endorsement"
      class="flex flex-wrap items-center gap-2 mt-4"
    >
      <select name="endorsement-id" class="input-sm max-w-xs" aria-label="Endorsement">
        <option value="">Select an endorsement</option>
        {Phoenix.HTML.Form.options_for_select(@options, nil)}
      </select>
      <.button size={:sm}>Add endorsement</.button>
      <.a navigate={@new_path}>New endorsement</.a>
    </form>

    <div class="mt-4">
      <.button id="done-editing" variant={:primary} size={:sm} phx-click="done-editing">
        Done
      </.button>
    </div>
    """
  end
end
