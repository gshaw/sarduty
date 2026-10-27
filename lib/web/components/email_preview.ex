defmodule Web.Components.EmailPreview do
  @moduledoc """
  An email as members get it, from its mailer's own HTML (#608, #609), at a phone's
  width. Inert, so its links, which go nowhere here, can't be selected. See
  /styles/email-preview.
  """
  use Phoenix.Component

  attr :id, :string, default: "email-preview"
  attr :subject, :string, required: true
  attr :html, :string, required: true, doc: "the mailer's HTML, already escaped"

  def email_preview(assigns) do
    ~H"""
    <div id={@id} class="email-preview">
      <p class="email-preview-subject">
        <span class="hint">Subject</span> {@subject}
      </p>
      <div class="email-preview-body" inert>{Phoenix.HTML.raw(@html)}</div>
    </div>
    """
  end
end
