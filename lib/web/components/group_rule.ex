defmodule Web.Components.GroupRule do
  @moduledoc """
  The group rule editor on a group's page: a card per clause, with its name, the
  qualifications a member must hold any of, and a menu to add one. The style guide's
  Build a group rule pattern renders it with made-up clauses.

  It takes plain maps, so the guide needs no database: each clause is
  `%{id, name, confirm, qualifications: [%{id, title, known?}], options: [{title, id}]}`.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [button: 1, icon: 1]

  attr :clauses, :list, required: true

  def clause_editor(assigns) do
    ~H"""
    <p class="text-text-muted">Set the qualifications members must hold to be in this group.</p>

    <div :for={clause <- @clauses} class="card mb-4">
      <div class="flex flex-wrap items-center justify-between gap-2 mb-2">
        <form
          id={"clause-name-form-#{clause.id}"}
          phx-change="rename-clause"
          phx-submit="rename-clause"
          class="flex flex-wrap items-center gap-2"
        >
          <input type="hidden" name="clause-id" value={clause.id} />
          <input
            type="text"
            name="name"
            id={"clause-name-#{clause.id}"}
            value={clause.name}
            placeholder="Name, for example First Aid"
            aria-label="Clause name"
            maxlength="60"
            phx-debounce="blur"
            class="input-sm font-semibold"
          />
          <h3 class="label">— member must hold any of:</h3>
        </form>
        <.button
          variant={:danger}
          size={:sm}
          phx-click="delete-clause"
          phx-value-clause-id={clause.id}
          data-confirm={clause.confirm}
        >
          Delete clause
        </.button>
      </div>

      <div class="flex flex-wrap gap-2 mb-2">
        <span
          :for={q <- clause.qualifications}
          id={"clause-qualification-#{q.id}"}
          class={["chip", !q.known? && "chip-danger"]}
        >
          {q.title}
          <button
            type="button"
            class="chip-remove"
            phx-click="remove-qualification"
            phx-value-qualification-id={q.id}
            title="Remove qualification"
            aria-label={"Remove #{q.title}"}
          >
            <.icon name="hero-x-mark-micro" />
          </button>
        </span>
        <span :if={clause.qualifications == []} class="hint">No qualifications yet</span>
      </div>

      <form phx-submit="add-qualification" class="flex flex-wrap items-center gap-2">
        <input type="hidden" name="clause-id" value={clause.id} />
        <select name="qualification-id" class="input-sm max-w-xs" aria-label="Qualification">
          <option value="">Select a qualification</option>
          {Phoenix.HTML.Form.options_for_select(clause.options, nil)}
        </select>
        <.button size={:sm}>Add qualification</.button>
      </form>
    </div>

    <div class="flex flex-wrap gap-2">
      <.button size={:sm} phx-click="add-clause">Add clause</.button>
      <.button id="done-editing" variant={:primary} size={:sm} phx-click="done-editing">
        Done
      </.button>
    </div>
    """
  end
end
