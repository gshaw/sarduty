defmodule Web.Components.CopyButton do
  @moduledoc """
  A small copy icon after a value, such as an address. Selecting it copies the value and
  shows Copied beside it for 2 seconds, through the sarduty:copy handler in app.js. See
  /styles/copy-button.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [icon: 1]

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :value, :string, required: true, doc: "the text to copy"
  attr :label, :string, required: true, doc: "what it copies, for screen readers: Copy address"

  def copy_button(assigns) do
    ~H"""
    <button
      :if={@value}
      id={@id}
      type="button"
      class="copy-button"
      value={@value}
      aria-label={@label}
      title={@label}
      phx-click={JS.dispatch("sarduty:copy", detail: %{status: "##{@id}-status"})}
    >
      <.icon name="hero-document-duplicate-micro" />
    </button>
    <span :if={@value} id={"#{@id}-status"} class="copy-status" aria-live="polite"></span>
    """
  end
end
