defmodule Web.Components.Core do
  @moduledoc """
  The components any page can use: flash, buttons, badges, form inputs, switches, and
  icons. The design system at /styles shows each one.
  """
  use Phoenix.Component

  use Gettext, backend: Web.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={["toast", @kind == :error && "toast-error"]}
      {@rest}
    >
      <.icon
        name={if @kind == :error, do: "hero-exclamation-circle-mini", else: "hero-check-circle-mini"}
        class="toast-icon"
      />
      <div class="toast-body">
        <span :if={@title} class="toast-title">{@title}</span>
        {msg}
      </div>
      <button type="button" class="toast-close" aria-label={gettext("Close")}>
        <.icon name="hero-x-mark-mini" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a button, or a link styled as one when given `navigate` or `href`.

  ## Examples

      <.button variant={:success}>Save</.button>
      <.button variant={:danger} size={:sm} phx-click="delete">Delete</.button>
      <.button navigate={~p"/login"} size={:sm}>Log in</.button>
  """
  attr :type, :string, default: nil

  attr :variant, :atom,
    default: :default,
    values: [:default, :primary, :secondary, :success, :warning, :danger, :link]

  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :navigate, :string, default: nil
  attr :href, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value method)

  slot :inner_block, required: true

  def button(assigns) do
    assigns = assign(assigns, :button_class, button_class(assigns))

    if assigns.navigate || assigns.href do
      ~H"""
      <.link navigate={@navigate} href={@href} class={@button_class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button type={@type} class={["phx-submit-loading:opacity-75", @button_class]} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  defp button_class(%{variant: variant, size: size, class: class}) do
    [
      "btn",
      variant != :default && "btn-#{variant}",
      size != :md && "btn-#{size}",
      class
    ]
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :trailing

  def form_actions(assigns) do
    ~H"""
    <div class={["form-actions flex flex-wrap", @class]}>
      <div class="flex gap-2 grow">
        {render_slot(@inner_block)}
      </div>
      <div :if={@trailing != []} class="flex gap-2">
        {render_slot(@trailing)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a badge.

  ## Examples

      <.badge>Draft</.badge>
      <.badge kind={:incident} title="Activity kind">Incident</.badge>
  """
  attr :kind, :atom,
    default: :default,
    values: [
      :default,
      :primary,
      :secondary,
      :success,
      :warning,
      :danger,
      :incident,
      :exercise,
      :event,
      :outline
    ]

  attr :rest, :global
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={["badge", @kind != :default && "badge-#{@kind}"]} {@rest}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block

  def spinner(assigns) do
    ~H"""
    <span class={["spinner-text", @class]} {@rest}>
      <span class="spinner" aria-hidden="true"></span>
      <span :if={@inner_block != []}>{render_slot(@inner_block)}</span>
    </span>
    """
  end

  slot :inner_block, required: true

  def hint(assigns) do
    ~H"""
    <div class="hint block mb-2">
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="label block mb-1">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Renders an error message: what to fix, in bold red, above the input.
  """
  attr :rest, :global
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <div class="mb-2 font-bold text-danger-text" {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc ~S"""
  Renders tabs: links to sibling pages, each with its own URL. Mark the page you're on
  with `current`, which sets `aria-current="page"`.

  ## Examples

      <.tabs label="Member">
        <:tab navigate={~p"/teams/#{@team}/members/#{@member.id}"} current>Attendance</:tab>
        <:tab navigate={~p"/teams/#{@team}/members/#{@member.id}/groups"}>Groups</:tab>
      </.tabs>
  """
  attr :label, :string, required: true, doc: "the aria-label of the nav"

  slot :tab, required: true do
    attr :navigate, :string, required: true
    attr :current, :boolean
  end

  def tabs(assigns) do
    ~H"""
    <nav class="tabs" aria-label={@label}>
      <.link :for={tab <- @tab} navigate={tab.navigate} aria-current={tab[:current] && "page"}>
        {render_slot(tab)}
      </.link>
    </nav>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :class, :any, default: nil
  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    # Only show errors for fields the user has typed in or submitted.
    errors = if used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class={["flex gap-3 items-start", @label && "mb-4"]}>
      <input type="hidden" name={@name} value="false" />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        class={@class}
        {@rest}
      />
      <div :if={@label}>
        <label for={@id} class="block cursor-pointer">{@label}</label>
        <.hint :if={@inner_block != []}>{render_slot(@inner_block)}</.hint>
        <.error :for={message <- @errors}>{message}</.error>
      </div>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={["mb-5", @errors != [] && "field-error"]}>
      <.label :if={@label != nil} for={@id}>{@label}</.label>
      <.hint :if={@inner_block != []}>{render_slot(@inner_block)}</.hint>
      <.error :for={msg <- @errors}>{msg}</.error>
      <select
        id={@id}
        name={@name}
        class={[@errors != [] && "is-invalid", @class]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={["mb-5", @errors != [] && "field-error"]}>
      <.label :if={@label != nil} for={@id}>{@label}</.label>
      <.hint :if={@inner_block != []}>{render_slot(@inner_block)}</.hint>
      <.error :for={msg <- @errors}>{msg}</.error>
      <textarea
        id={@id}
        name={@name}
        class={[@errors != [] && "is-invalid", @class]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class={["mb-5", @errors != [] && "field-error"]}>
      <.label :if={@label != nil} for={@id}>{@label}</.label>
      <.hint :if={@inner_block != []}>{render_slot(@inner_block)}</.hint>
      <.error :for={msg <- @errors}>{msg}</.error>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[@errors != [] && "is-invalid", @class]}
        {@rest}
      />
    </div>
    """
  end

  @doc """
  Renders a switch: a setting that takes effect the moment it's tapped, with the label on
  the leading edge and the switch on the trailing edge. Inside a form with a save button,
  use a checkbox instead. See /styles/forms.

  `compact` puts a small, muted label and the switch together on the trailing edge. It's
  for one page-level setting under the page's main action, not a list of settings.

  ## Examples

      <.switch id="email-switch" label="Email me when a refresh fails">
        Sent to the address on your account.
      </.switch>

      <.switch id="sound-switch" label="Sound" compact />
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :checked, :boolean, default: false
  attr :compact, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled name value)

  slot :inner_block, doc: "an optional hint under the label, not shown when compact"

  def switch(%{compact: true} = assigns) do
    ~H"""
    <div class={["switch-row justify-end", @class]}>
      <label for={@id} class="hint cursor-pointer">{@label}</label>
      <input type="checkbox" role="switch" id={@id} class="switch" checked={@checked} {@rest} />
    </div>
    """
  end

  def switch(assigns) do
    ~H"""
    <div class={["switch-row", @class]}>
      <div class="grow">
        <label for={@id} class="block cursor-pointer font-semibold">{@label}</label>
        <span :if={@inner_block != []} id={"#{@id}-hint"} class="hint block">
          {render_slot(@inner_block)}
        </span>
      </div>
      <input
        type="checkbox"
        role="switch"
        id={@id}
        class="switch"
        checked={@checked}
        aria-describedby={@inner_block != [] && "#{@id}-hint"}
        {@rest}
      />
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in four styles: outline and solid at 24px, mini at 20px, and micro at
  16px, picked with the `-solid`, `-mini`, and `-micro` suffix. Each draws at its own
  size, so an icon needs no size class. It takes the text colour.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-chevron-right-micro" class="breadcrumb-separator" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 md:translate-y-0 md:scale-95",
         "opacity-100 translate-y-0 md:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 md:scale-100",
         "opacity-0 translate-y-4 md:translate-y-0 md:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(Web.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(Web.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
