defmodule Web.Components.EmailPreview do
  @moduledoc """
  An email, or a text, as members get it (#608, #609, #857): before it's sent, on Send a
  reminder and Send an update, and after, in a demo's Outbox. One look for both. See
  /styles/email-preview.
  """
  use Phoenix.Component

  import Web.Components.A
  import Web.Components.Core, only: [icon: 1]

  attr :id, :string, default: "email-preview"
  attr :subject, :string, default: nil, doc: "nil for a text"
  attr :html, :string, default: nil, doc: "the mailer's HTML, already escaped"
  attr :text, :string, default: nil, doc: "plain text, when there is no HTML"
  attr :from, :string, default: nil, doc: "with `to` and `date`, a mail app's header"
  attr :to, :string, default: nil
  attr :date, :string, default: nil, doc: "already formatted"

  attr :attachments, :list,
    default: [],
    doc: "maps of `id`, `name`, `size` (bytes), and `href` to open it, nil before it's sent"

  attr :live, :boolean, default: false, doc: "links work; otherwise the email is inert"
  attr :width, :atom, default: :phone, values: [:phone, :wide]

  def email_preview(assigns) do
    ~H"""
    <div id={@id} class={["email-preview", @width == :wide && "email-preview-wide"]}>
      <dl :if={@to} class="email-preview-head">
        <dt>From</dt>
        <dd id={"#{@id}-from"}>{@from || "SAR Duty"}</dd>
        <dt>To</dt>
        <dd id={"#{@id}-to"}>{@to}</dd>
        <dt :if={@subject}>Subject</dt>
        <dd :if={@subject}>{@subject}</dd>
        <dt :if={@date}>Date</dt>
        <dd :if={@date}>{@date}</dd>
      </dl>
      <p :if={!@to} class="email-preview-subject">
        <span class="hint">Subject</span> {@subject}
      </p>
      <div :if={@html} id={"#{@id}-html"} class="email-preview-body" inert={!@live}>
        {Phoenix.HTML.raw(@html)}
      </div>
      <%!-- pre-wrap shows every space, so the text touches the tags: no indent or gap --%>
      <div
        :if={!@html && @text}
        id={"#{@id}-text"}
        class="email-preview-body whitespace-pre-wrap break-words"
        inert={!@live}
        phx-no-format
      ><.linked_text text={String.trim(@text)} /></div>
      <ul :if={@attachments != []} id={"#{@id}-attachments"} class="email-preview-attachments">
        <li :for={attachment <- @attachments}>
          <.attachment_tile id={"#{@id}-attachment-#{attachment.id}"} attachment={attachment} />
        </li>
      </ul>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :attachment, :map, required: true

  # A file at the foot of the email, big enough to see and tap, as a mail app shows one.
  defp attachment_tile(%{attachment: %{href: nil}} = assigns) do
    ~H"""
    <div id={@id} class="email-attachment media">
      <.icon name="file" size={:lg} />
      <span><.attachment_text attachment={@attachment} /></span>
    </div>
    """
  end

  defp attachment_tile(assigns) do
    ~H"""
    <.a
      id={@id}
      kind={:custom}
      href={@attachment.href}
      target="_blank"
      class="email-attachment media"
    ><.icon name="file" size={:lg} /><span><.attachment_text attachment={@attachment} /></span></.a>
    """
  end

  attr :attachment, :map, required: true

  defp attachment_text(assigns) do
    ~H"""
    <span class="email-attachment-name">{@attachment.name}</span>
    <span :if={@attachment[:size]} class="hint">{Service.Format.file_size(@attachment.size)}</span>
    """
  end

  attr :text, :string, required: true

  # Plain text with its web addresses as links, so a reply link can be followed.
  defp linked_text(assigns) do
    assigns = assign(assigns, :parts, split_links(assigns.text))

    # One line: the body is pre-wrap, so any space here would show.
    ~H"""
    <span phx-no-format><%= for {kind, part} <- @parts do %><.a :if={kind == :link} href={part}>{part}</.a><span :if={kind == :text}>{part}</span><% end %></span>
    """
  end

  @link ~r{https?://[^\s<>"]+}

  @doc false
  def split_links(text) do
    @link
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(&if(Regex.match?(~r{\Ahttps?://}, &1), do: {:link, &1}, else: {:text, &1}))
  end
end
