defmodule Web.Components.Unsaved do
  @moduledoc """
  "Not saved yet", beside an editor's Save while what's on the page differs from what's
  saved: Change report and Change form. While it shows, leaving the page asks first
  (assets/js/unsaved.js); Save, and a link marked `data-leave-ok` such as Cancel, don't.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :unsaved, :boolean, required: true

  def unsaved(assigns) do
    ~H"""
    <span
      id={@id}
      class="hint self-center"
      phx-hook="Unsaved"
      data-unsaved={to_string(@unsaved)}
      hidden={!@unsaved}
    >Not saved yet</span>
    """
  end
end
