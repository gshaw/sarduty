defmodule Web.Components.Unsaved do
  @moduledoc """
  "Not saved yet", beside an editor's Save while what's on the page differs from what's
  saved: Change report and Change form. Once the person's draft keeps the changes
  (App.Operation.SaveDraft, #1089), it says so, and leaving asks nothing: nothing is
  lost. Leaving asks first (assets/js/unsaved.js) only while something isn't kept yet:
  changes no draft keeps, an ask AI is still answering (`saving`), or typing the
  server hasn't kept, which `rev` tells it, a number that goes up each time it keeps
  one. Save, and a link marked `data-leave-ok` such as Close, never ask.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :unsaved, :boolean, required: true
  attr :kept, :boolean, default: false
  attr :saving, :boolean, default: false
  attr :rev, :integer, default: 0

  def unsaved(assigns) do
    ~H"""
    <span
      id={@id}
      class="hint self-center"
      phx-hook="Unsaved"
      data-unsaved={to_string(@unsaved)}
      data-kept={to_string(@kept)}
      data-saving={to_string(@saving)}
      data-rev={@rev}
      hidden={!@unsaved}
    >{if @kept, do: "Not saved yet. Kept for you until you save.", else: "Not saved yet"}</span>
    """
  end
end
