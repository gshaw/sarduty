defmodule Web.Components.Messages do
  @moduledoc """
  What a page tells people: banners, warning text, empty states, the error summary, the
  result band, and the confirm dialog. Toasts are `Web.Components.Core.flash/1`. Their CSS is
  assets/css/components/messages.css; the style guide at /styles shows each one.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [button: 1, icon: 1, translate_error: 1]

  @doc """
  Renders a banner: something true about the page until it changes.

  ## Examples

      <.banner kind={:success} title="Letters sent" id="letters-sent">
        <p>12 tax credit letters created for 2025.</p>
      </.banner>
  """
  attr :kind, :atom, default: :info, values: [:info, :success, :warning, :danger]
  attr :title, :string, required: true
  attr :role, :string, default: nil, doc: "status, alert, or region; it follows the kind"
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def banner(assigns) do
    assigns = assign(assigns, :role, assigns.role || banner_role(assigns.kind))

    ~H"""
    <div
      class={["banner", @kind != :info && "banner-#{@kind}", @class]}
      role={@role}
      aria-label={@role == "region" && @title}
      {@rest}
    >
      <div class="banner-title">
        <.icon name={kind_icon(@kind)} />{@title}
      </div>
      <div class="banner-body">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp banner_role(:success), do: "status"
  defp banner_role(:danger), do: "alert"
  defp banner_role(_kind), do: "region"

  @doc """
  Renders warning text: a consequence people must know before they act, right before
  the action.
  """
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def warning_text(assigns) do
    ~H"""
    <div class={["warning-text", @class]} {@rest}>
      <.icon name="triangle-alert" size={:lg} />
      <span>{render_slot(@inner_block)}</span>
    </div>
    """
  end

  @doc """
  Renders an empty state: why a list is empty and what to do.

  ## Examples

      <.empty_state id="no-groups" title="No groups yet">
        SAR Duty copies groups from D4H when it refreshes.
      </.empty_state>
  """
  attr :title, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true
  slot :action, doc: "a button or link to fix it"

  def empty_state(assigns) do
    ~H"""
    <div class={["empty-state", @class]} {@rest}>
      <strong>{@title}</strong>
      <p>{render_slot(@inner_block)}</p>
      {render_slot(@action)}
    </div>
    """
  end

  @doc """
  Renders an error summary at the top of a long form after a failed save. Each line is
  the field's error, word for word, linked to the field. Renders nothing without errors.

  ## Examples

      <.error_summary form={@form} />
  """
  attr :form, Phoenix.HTML.Form, required: true

  def error_summary(assigns) do
    assigns = assign(assigns, :errors, form_errors(assigns.form))

    ~H"""
    <div :if={@errors != []} id={"#{@form.id}-errors"} class="error-summary" role="alert">
      <h2>There is a problem</h2>
      <ul>
        <li :for={{id, message} <- @errors}><a href={"##{id}"}>{message}</a></li>
      </ul>
    </div>
    """
  end

  # A form's errors as {field id, message}, after a failed save. Not while typing: a
  # :validate changeset shows its errors on the fields only.
  defp form_errors(%Phoenix.HTML.Form{source: %Ecto.Changeset{action: action} = changeset} = form)
       when action not in [nil, :validate, :ignore] do
    for {field, error} <- changeset.errors,
        do: {Phoenix.HTML.Form.input_id(form, field), translate_error(error)}
  end

  defp form_errors(_form), do: []

  @doc """
  Renders a result band: the outcome of a check, big and in colour, such as a verified ID
  card or a scan on Take attendance.

  ## Examples

      <.band kind={:success} title="Active member">Verified just now</.band>
  """
  attr :kind, :atom, required: true, values: [:info, :success, :warning, :danger]
  attr :title, :string, required: true
  attr :icon, :string, default: nil, doc: "an icon in place of the kind's"
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block

  def band(assigns) do
    ~H"""
    <div class={["band", "band-#{@kind}", @class]} {@rest}>
      <.icon name={@icon || kind_icon(@kind)} class="band-icon" />
      <div>
        <div class="band-title">{@title}</div>
        <div :if={@inner_block != []} class="band-detail">{render_slot(@inner_block)}</div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the dialog a `data-confirm` button asks in (#651). The root layout renders one,
  empty, and assets/js/confirm_dialog.js fills it from the button that asked:

  - `data-confirm`: the question, then any sentences after it as the body.
  - `data-confirm-button`: the action, such as "Delete group". The button's own text
    otherwise. Red when the button is, or has `data-confirm-danger` (an Actions link's
    Delete), blue otherwise.
  - `data-confirm-list`: what's lost, as a JSON array of sentences.
  - `data-confirm-warning`: a bold last line, such as "D4H can't bring it back."
  - `data-confirm-check`: a check box the action waits on. Only for a change that takes
    other things with it, or stops a tax credit letter verifying.
  - `data-confirm-type`, with `data-confirm-type-label`: text to type before the action
    turns on, matched ignoring case and spaces.
  - `data-confirm-alt` and `data-confirm-alt-href`: a link that's a better way out than
    going ahead.

  Cancel has the focus, so Enter by reflex does nothing. The style guide renders each
  state with `open`, in place on the page. A page that asks a question itself renders
  one more, with `phx-hook="AskDialog"` and `data-confirm-event` and `data-cancel-event`
  for the answers: it opens as soon as it renders (Add activity's template switch).
  """
  attr :id, :string, default: "confirm-dialog"
  attr :open, :boolean, default: false, doc: "shown in place, for the style guide"
  attr :question, :string, default: nil
  attr :body, :string, default: nil
  attr :list, :list, default: []
  attr :warning, :string, default: nil
  attr :check, :string, default: nil
  attr :checked, :boolean, default: false
  attr :type, :string, default: nil
  attr :type_label, :string, default: "Type this to confirm"
  attr :typed, :string, default: nil
  attr :action, :string, default: nil
  attr :variant, :atom, default: :primary, values: [:primary, :danger, :default]
  attr :alt, :string, default: nil
  attr :alt_href, :string, default: nil
  attr :rest, :global

  def confirm_dialog(assigns) do
    assigns = assign(assigns, :locked, confirm_locked?(assigns))

    ~H"""
    <dialog
      id={@id}
      class="confirm-dialog"
      open={@open}
      aria-labelledby={"#{@id}-question"}
      data-confirm-dialog
      {@rest}
    >
      <form method="dialog">
        <h2 id={"#{@id}-question"} class="confirm-dialog-question">{@question}</h2>
        <p data-part="body" hidden={!@body}>{@body}</p>
        <ul data-part="list" hidden={@list == []}>
          <li :for={item <- @list}>{item}</li>
        </ul>
        <p data-part="warning" class="confirm-dialog-warning" hidden={!@warning}>{@warning}</p>
        <label data-part="check" class="confirm-dialog-check" hidden={!@check}>
          <input type="checkbox" checked={@checked} />
          <span>{@check}</span>
        </label>
        <div data-part="type" class="confirm-dialog-type" hidden={!@type}>
          <label for={"#{@id}-typed"}>{@type_label}</label>
          <code>{@type}</code>
          <input id={"#{@id}-typed"} type="text" autocomplete="off" value={@typed} />
        </div>
        <div class="confirm-dialog-actions">
          <.button data-part="alt" variant={:primary} href={@alt_href || "#"} hidden={!@alt}>
            {@alt}
          </.button>
          <.button variant={@variant} value="confirm" disabled={@locked}>{@action}</.button>
          <.button value="cancel">Cancel</.button>
        </div>
      </form>
    </dialog>
    """
  end

  @check_from 10

  @doc """
  The `data-confirm` attributes for a button that emails `count` members: the question
  and `lines` as its body. From #{@check_from} members up, the lines are a list and the
  send waits on a check box naming the count, so nobody emails the whole team by reflex.
  """
  def send_confirm(count, question, lines) do
    if count < @check_from do
      %{"data-confirm" => Enum.join([question | lines], " ")}
    else
      members = Service.Format.count(count, one: "%d member", many: "%d members")

      %{
        "data-confirm" => question,
        "data-confirm-list" => Jason.encode!(lines),
        "data-confirm-warning" => "Emails cannot be taken back.",
        "data-confirm-check" => "I understand #{members} get this email."
      }
    end
  end

  # The JS does the same as the person ticks or types.
  defp confirm_locked?(assigns) do
    (assigns.check != nil and not assigns.checked) or
      (assigns.type != nil and typed_key(assigns.typed) != typed_key(assigns.type))
  end

  defp typed_key(nil), do: ""
  defp typed_key(text), do: text |> String.downcase() |> String.replace(~r/\s+/, "")

  defp kind_icon(:success), do: "circle-check"
  defp kind_icon(:info), do: "info"
  defp kind_icon(:warning), do: "triangle-alert"
  defp kind_icon(:danger), do: "circle-alert"
end
