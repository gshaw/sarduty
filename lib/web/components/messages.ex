defmodule Web.Components.Messages do
  @moduledoc """
  What a page tells people: banners, warning text, empty states, the error summary, and
  the result band. Toasts are `Web.Components.Core.flash/1`. Their CSS is
  assets/css/components/messages.css; the style guide at /styles shows each one.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [icon: 1]

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
        <.icon name={kind_icon_mini(@kind)} />{@title}
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
      <.icon name="hero-exclamation-triangle" />
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
        do: {Phoenix.HTML.Form.input_id(form, field), Web.Components.Core.translate_error(error)}
  end

  defp form_errors(_form), do: []

  @doc """
  Renders a result band: the outcome of a check, big and in colour, such as a verified ID
  card or a scan at the door.

  ## Examples

      <.band kind={:success} title="Active member">Verified just now</.band>
  """
  attr :kind, :atom, required: true, values: [:info, :success, :warning, :danger]
  attr :title, :string, required: true
  attr :icon, :string, default: nil, doc: "an outline icon in place of the kind's"
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block

  def band(assigns) do
    ~H"""
    <div class={["band", "band-#{@kind}", @class]} {@rest}>
      <.icon name={@icon || kind_icon(@kind)} />
      <div>
        <div class="band-title">{@title}</div>
        <div :if={@inner_block != []} class="band-detail">{render_slot(@inner_block)}</div>
      </div>
    </div>
    """
  end

  defp kind_icon(:success), do: "hero-check-circle"
  defp kind_icon(:info), do: "hero-information-circle"
  defp kind_icon(:warning), do: "hero-exclamation-triangle"
  defp kind_icon(:danger), do: "hero-exclamation-circle"

  defp kind_icon_mini(:success), do: "hero-check-circle-mini"
  defp kind_icon_mini(:info), do: "hero-information-circle-mini"
  defp kind_icon_mini(:warning), do: "hero-exclamation-triangle-mini"
  defp kind_icon_mini(:danger), do: "hero-exclamation-circle-mini"
end
