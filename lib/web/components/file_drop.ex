defmodule Web.Components.FileDrop do
  @moduledoc """
  A file drop: one box for every upload, which takes a file dropped on it, pasted on the
  page, or picked with the browser's own button. On a phone or iPad it is the button
  alone. Its CSS is assets/css/components/file_drop.css, the paste is the FileDrop hook
  (assets/js/file_drop.js), and /styles/file-drop shows it.
  """
  use Phoenix.Component

  import Web.Components.A
  import Web.Components.Core, only: [error: 1, hint: 1, icon: 1, label: 1, upload_error: 3]

  @doc """
  Renders a file drop for one upload from `allow_upload/3`, with its label, hint, errors,
  and the file chosen. Selecting Remove sends `cancel-upload` with the entry's `ref`.
  `kinds` names what it takes, for the box and the errors: "a photo or a PDF". `errors`
  are more messages for the field, such as the changeset's. `current` shows the file it
  has now, such as a logo, above the box.

  ## Examples

      <.file_drop id="certificate-file" upload={@uploads.certificate} label="Certificate"
        kinds="a photo or a PDF">
        A photo or a PDF, up to 10 MB.
      </.file_drop>
  """
  attr :id, :string, required: true
  attr :upload, :map, required: true
  attr :label, :string, required: true
  attr :kinds, :string, required: true
  attr :errors, :list, default: []
  attr :class, :any, default: nil, doc: "on the box"
  slot :inner_block, doc: "the hint"
  slot :current, doc: "the file it has now"

  def file_drop(assigns) do
    %{upload: upload, kinds: kinds, errors: errors} = assigns

    # The upload's errors and each file's, then the field's own.
    entry_errors = Enum.flat_map(upload.entries, &upload_errors(upload, &1))

    messages =
      (upload_errors(upload) ++ entry_errors)
      |> Enum.map(&upload_error(&1, upload, kinds))
      |> Enum.concat(errors)
      |> Enum.uniq()

    assigns = assign(assigns, messages: messages)

    ~H"""
    <div id={@id} class={["mb-6", @messages != [] && "field-error"]}>
      <.label for={@upload.ref}>{@label}</.label>
      <.hint :if={@inner_block != []}>{render_slot(@inner_block)}</.hint>
      <.error :for={message <- @messages}>{message}</.error>
      <div :if={@current != []} class="mb-2">{render_slot(@current)}</div>
      <div
        id={"#{@id}-drop"}
        class={["file-drop", @messages != [] && "is-invalid", @class]}
        phx-drop-target={@upload.ref}
        phx-hook="FileDrop"
        data-upload={@upload.name}
      >
        <div :for={entry <- @upload.entries} id={"#{@id}-#{entry.ref}"} class="file-drop-file media">
          <.live_img_preview
            :if={String.starts_with?(entry.client_type, "image/")}
            entry={entry}
            class="file-drop-thumb"
          />
          <span :if={!String.starts_with?(entry.client_type, "image/")} class="file-drop-doc">
            <.icon name="hero-document" class="size-12" />
          </span>
          <div>
            <span class="block">{entry.client_name}</span>
            <span class="hint block">{Service.Format.file_size(entry.client_size)}</span>
            <.a
              href="#"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
              aria-label={"Remove #{entry.client_name}"}
            >Remove</.a>
          </div>
        </div>
        <%!-- The icon's classes are utilities, which win over component CSS, so the span
          is what hides and colours it. --%>
        <span class="file-drop-icon" aria-hidden="true">
          <.icon name="hero-arrow-up-tray" class="size-8" />
        </span>
        <span class="file-drop-text">Drop {@kinds} here, or paste one.</span>
        <.live_file_input upload={@upload} />
      </div>
    </div>
    """
  end
end
