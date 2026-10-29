defmodule Web.Components.Core do
  @moduledoc """
  The components any page can use: flash, buttons, badges, form inputs, switches, and
  icons. The design system at /styles shows each one.
  """
  use Phoenix.Component

  use Gettext, backend: Web.Gettext

  alias Phoenix.LiveView.JS

  # The icons in assets/icons, so <.icon> and <.button icon> refuse any other name: a
  # written-out name when it compiles, a worked-out one when it renders.
  @icon_files "../../../assets/icons/*.svg" |> Path.expand(__DIR__) |> Path.wildcard()
  for file <- @icon_files, do: @external_resource(file)
  @icon_names Enum.map(@icon_files, &Path.basename(&1, ".svg"))

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
      <.icon name={if @kind == :error, do: "circle-alert", else: "circle-check"} class="toast-icon" />
      <div class="toast-body">
        <span :if={@title} class="toast-title">{@title}</span>
        {msg}
      </div>
      <button type="button" class="toast-close" aria-label={gettext("Close")}>
        <.icon name="x" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a button, or a link styled as one when given `navigate` or `href`.

  A button whose event waits on email, D4H, Records, Wallet, Mapbox, or a PDF gets
  `phx-disable-with` naming the slow thing, like "Sending…": it disables the button and
  shows a spinner until the event answers. Web.SlowButtonTest fails without it. See
  /styles/button#slow.

  `icon` leads with an icon, such as `icon="rotate-ccw-square"`. The button draws it
  itself, so phx-disable-with, which puts back only the text, keeps it,
  and the spinner takes its place while it waits.

  ## Examples

      <.button variant={:success}>Save</.button>
      <.button variant={:danger} size={:sm} phx-click="delete">Delete</.button>
      <.button phx-click="email" phx-disable-with="Sending…">Email letter</.button>
      <.button icon="rotate-ccw-square" phx-click="rotate">Rotate left</.button>
      <.button navigate={~p"/login"}>Log in</.button>
  """
  attr :type, :string, default: nil

  attr :variant, :atom,
    default: :default,
    values: [:default, :primary, :secondary, :success, :warning, :danger, :link]

  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :navigate, :string, default: nil
  attr :href, :string, default: nil
  attr :class, :string, default: nil
  attr :icon, :string, default: nil, values: [nil | @icon_names]
  attr :rest, :global, include: ~w(disabled form name value method)

  slot :inner_block, required: true

  def button(assigns) do
    assigns =
      assign(assigns, button_class: button_class(assigns), icon_style: icon_style(assigns))

    if assigns.navigate || assigns.href do
      ~H"""
      <.link
        navigate={@navigate}
        href={@href}
        class={@button_class}
        style={@icon_style}
        {@rest}
      >
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button
        type={@type}
        class={["phx-submit-loading:opacity-75", @button_class]}
        style={@icon_style}
        {@rest}
      >
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  defp button_class(%{variant: variant, size: size, class: class, icon: icon}) do
    [
      "btn",
      variant != :default && "btn-#{variant}",
      size != :md && "btn-#{size}",
      icon && "btn-icon",
      class
    ]
  end

  # The icon's variable, from assets/vendor/icons.js. btn.css sizes it to the button.
  defp icon_style(%{icon: nil}), do: nil
  defp icon_style(%{icon: icon}), do: "--btn-icon: var(--icon-#{icon})"

  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :trailing

  # The buttons wrap onto a new line when they don't fit, so a row never runs off a phone.
  def form_actions(assigns) do
    ~H"""
    <div class={["form-actions flex flex-wrap", @class]}>
      <div class="flex flex-wrap gap-2 grow">
        {render_slot(@inner_block)}
      </div>
      <div :if={@trailing != []} class="flex flex-wrap gap-2">
        {render_slot(@trailing)}
      </div>
    </div>
    """
  end

  @doc """
  The filters above a list. Changing one sends `change`, and so does Enter in a
  text box: without phx-submit the browser posts the form itself and gets a 404 (#333).
  """
  attr :for, :any, required: true
  attr :id, :string, required: true
  attr :class, :string, default: "filter-form"
  attr :rest, :global
  slot :inner_block, required: true

  def filter_form(assigns) do
    ~H"""
    <.form for={@for} id={@id} phx-change="change" phx-submit="change" class={@class} {@rest}>
      {render_slot(@inner_block)}
    </.form>
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
      :chores,
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

    * `type="combobox"` is a select you type into, for a list that can run past about 15
      options. See `combobox/1`

    * `type="radios"` is one answer from a few choices, all in view, with `options` as
      `{label, value}` or `{label, value, hint}`

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
    values: ~w(checkbox color combobox date datetime-local email file hidden month number password
               radio radios range rich_text search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :class, :any, default: nil
  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"

  attr :options, :list,
    doc:
      "a select's options for options_for_select/2; radios' {label, value} or {label, value, hint}"

  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :clearable, :boolean,
    default: false,
    doc: "for a combobox: lists the prompt first, so picking it empties the value"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :inner_block
  slot :below, doc: "under the box, such as what a time box read, or buttons that fill it"

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    # Only show errors for fields the user has typed in, or after a failed save, as the
    # error summary does. A form sends nothing for radios none of which is checked, so
    # used_input?/1 alone never marks them.
    errors = if used_input?(field) or saved?(field.form), do: field.errors, else: []

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

  # One answer, every choice in view. Options are {label, value}, or {label, value, hint}
  # for a line under the choice saying what it covers. The first radio has the field's id,
  # so the error summary's link lands on it. See /styles/forms.
  def input(%{type: "radios"} = assigns) do
    assigns = assign(assigns, :choices, Enum.with_index(assigns.options, &radio_choice/2))

    ~H"""
    <fieldset id={"#{@id}-choices"} class={["mb-6", @errors != [] && "field-error"]}>
      <legend class="label mb-1">{@label}</legend>
      <.hint :if={@inner_block != []}>{render_slot(@inner_block)}</.hint>
      <.error :for={msg <- @errors}>{msg}</.error>
      <label :for={{label, value, hint, i} <- @choices} class={["choice", hint && "mb-3"]}>
        <input
          type="radio"
          id={if i == 0, do: @id, else: "#{@id}_#{value}"}
          name={@name}
          value={value}
          checked={to_string(@value) == to_string(value)}
          {@rest}
        />
        <span>
          {label}
          <span :if={hint} class="hint block">{hint}</span>
        </span>
      </label>
    </fieldset>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={["mb-6", @errors != [] && "field-error"]}>
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

  def input(%{type: "combobox"} = assigns) do
    ~H"""
    <div class={["mb-6", @errors != [] && "field-error"]}>
      <.label :if={@label != nil} for={@id}>{@label}</.label>
      <.hint :if={@inner_block != []}>{render_slot(@inner_block)}</.hint>
      <.error :for={msg <- @errors}>{msg}</.error>
      <.combobox
        id={@id}
        name={@name}
        value={@value}
        options={@options}
        prompt={@prompt}
        clearable={@clearable}
        class={[@errors != [] && "is-invalid", @class]}
        {@rest}
      />
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={["mb-6", @errors != [] && "field-error"]}>
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

  # Text with bold, italics, links, and lists, saved as HTML (#599). Trix draws the editor
  # from the hidden input; LiveView leaves it alone. The link box opens under the selected
  # text; its inputs stay disabled, so the form never sends them, until Trix opens it. See
  # /styles/rich-text.
  def input(%{type: "rich_text"} = assigns) do
    ~H"""
    <div class={["mb-6", @errors != [] && "field-error"]}>
      <.label :if={@label != nil} for={"#{@id}-editor"}>{@label}</.label>
      <.hint :if={@inner_block != []}>{render_slot(@inner_block)}</.hint>
      <.error :for={msg <- @errors}>{msg}</.error>
      <div
        id={"#{@id}-rich-text"}
        class={["rich-text", @errors != [] && "is-invalid", @class]}
        phx-hook="RichText"
        phx-update="ignore"
      >
        <input type="hidden" id={@id} name={@name} value={@value} />
        <trix-toolbar id={"#{@id}-toolbar"} class="rich-text-toolbar">
          <div class="rich-text-buttons">
            <.rich_text_button attribute="bold" key="b" icon="bold" title="Bold" />
            <.rich_text_button attribute="italic" key="i" icon="italic" title="Italic" />
            <.rich_text_button
              attribute="href"
              action="link"
              key="k"
              icon="link"
              title="Link"
            />
            <.rich_text_button attribute="bullet" icon="list" title="Bulleted list" />
            <.rich_text_button
              attribute="number"
              icon="list-ordered"
              title="Numbered list"
            />
          </div>
          <div data-trix-dialogs>
            <div class="rich-text-dialog" data-trix-dialog="href" data-trix-dialog-attribute="href">
              <div class="rich-text-dialog-row">
                <input
                  type="url"
                  name="href"
                  class="input-sm"
                  placeholder="https://"
                  aria-label="Link"
                  autocomplete="off"
                  data-1p-ignore
                  data-trix-input
                  data-trix-validate-href
                  required
                  disabled
                />
                <.button type="button" size={:sm} data-trix-method="setAttribute">Add link</.button>
                <.button
                  type="button"
                  size={:sm}
                  class="rich-text-remove-link"
                  data-trix-method="removeAttribute"
                >
                  Remove link
                </.button>
              </div>
            </div>
          </div>
        </trix-toolbar>
        <trix-editor
          id={"#{@id}-editor"}
          input={@id}
          toolbar={"#{@id}-toolbar"}
          class="rich-text-editor prose"
          {@rest}
        >
        </trix-editor>
      </div>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class={["mb-6", @errors != [] && "field-error"]}>
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
      {render_slot(@below)}
    </div>
    """
  end

  defp radio_choice({label, value}, i), do: {label, value, nil, i}
  defp radio_choice({label, value, hint}, i), do: {label, value, hint, i}

  # A changeset form after a failed save: its action is :insert or :update, not :validate.
  defp saved?(%Phoenix.HTML.Form{source: %Ecto.Changeset{action: action}}),
    do: action not in [nil, :validate, :ignore]

  defp saved?(_form), do: false

  attr :attribute, :string, required: true
  attr :action, :string, default: nil
  attr :key, :string, default: nil
  attr :icon, :string, required: true, values: @icon_names
  attr :title, :string, required: true

  # Trix's own buttons: it reads the data attributes and marks the active one.
  defp rich_text_button(assigns) do
    ~H"""
    <button
      type="button"
      class="rich-text-button"
      data-trix-attribute={@attribute}
      data-trix-action={@action}
      data-trix-key={@key}
      title={@title}
      aria-label={@title}
      tabindex="-1"
    >
      <.icon name={@icon} />
    </button>
    """
  end

  @doc """
  Renders a select you type into (#324): a text box that lists the options containing every
  word typed. The hidden `<select>` is what the form submits, so the event and its params
  are the same as for a select. `options` take `options_for_select/2`'s shape, so
  `{group, [{name, value}]}` lists the options under a heading per group. `<.input
  type="combobox">` adds the label; use this one where the field has an aria-label
  instead. `size={:sm}` is for a row of small controls. The x at its end clears it. See
  /styles/combobox.

  ## Examples

      <.input type="combobox" name="group_id" id="group-id" label="Group" prompt="Select a group"
        options={@options} value="" />

      <.combobox id="target" name="target" size={:sm} options={@options}
        aria-label="Group or endorsement" />
  """
  attr :id, :string, required: true, doc: "the text box's id, for its label"
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :options, :list, required: true

  attr :prompt, :string,
    default: nil,
    doc: "the select's empty option, sent when nothing is picked"

  attr :clearable, :boolean,
    default: false,
    doc: "lists the prompt first, so picking it empties the value, as a filter's All"

  # Not "name": Safari offers contacts to a field whose placeholder says it.
  attr :placeholder, :string, default: "Type to search"
  attr :size, :atom, values: [:md, :sm], default: :md
  attr :class, :any, default: nil, doc: "on the wrapper; is-invalid marks the text box"
  attr :rest, :global, include: ~w(disabled)

  def combobox(assigns) do
    ~H"""
    <div
      id={"#{@id}-combobox"}
      class={["combobox", @size == :sm && "input-sm", @class]}
      phx-hook="Combobox"
      data-clearable={@clearable}
    >
      <select id={"#{@id}-select"} name={@name} class="hidden" tabindex="-1" aria-hidden="true">
        <option value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <div id={"#{@id}-ui"} phx-update="ignore">
        <div class="combobox-input">
          <input
            type="text"
            id={@id}
            role="combobox"
            aria-autocomplete="list"
            aria-expanded="false"
            aria-controls={"#{@id}-listbox"}
            autocomplete="off"
            placeholder={@placeholder}
            class={@size == :sm && "input-sm"}
            {@rest}
          />
          <button type="button" id={"#{@id}-clear"} class="combobox-clear" aria-label="Clear">
            <.icon name="x" />
          </button>
          <.icon name="chevron-down" class="combobox-chevron" />
        </div>
        <ul id={"#{@id}-listbox"} role="listbox" class="combobox-list" hidden></ul>
      </div>
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
  Renders an icon: one of [Lucide](https://lucide.dev)'s, copied into `assets/icons` by
  `bin/icons`. It takes the text colour.

  `size` is `:sm` (16px) beside small text, `:md` (20px) beside body text, and `:lg`
  (24px) on its own line. Lines are 1.5px at every size. The plugin in
  `assets/vendor/icons.js` builds a class for each file, and `.icon` in
  `components/icon.css` draws it. Every icon is on the style guide's Icons page.

  ## Examples

      <.icon name="x" size={:lg} />
      <.icon name="chevron-right" size={:sm} class="breadcrumb-separator" />
      <.icon name="rotate-ccw-square" />
  """
  attr :name, :string, required: true, values: @icon_names
  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :class, :any, default: nil

  def icon(%{name: name} = assigns) when name in @icon_names do
    ~H"""
    <span class={["icon", "icon-#{@name}", @size != :md && "icon-#{@size}", @class]} />
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
  What to do about a LiveView upload's error, for its `<.error>`. `kinds` names the files
  the upload takes, such as "a photo or a PDF".
  """
  def upload_error(:too_large, upload, _kinds),
    do: "That file is too large. Use one under #{Service.Format.file_size(upload.max_file_size)}."

  def upload_error(:not_accepted, _upload, kinds), do: "Select #{kinds}."
  def upload_error(:too_many_files, _upload, _kinds), do: "Select one file."
  def upload_error(_error, _upload, _kinds), do: "That file did not upload. Try again."

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
