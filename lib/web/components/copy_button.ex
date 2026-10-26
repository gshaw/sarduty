defmodule Web.Components.CopyButton do
  @moduledoc """
  A small copy icon after a value, such as an address, or in the corner of a code block.
  Pass the value as shown in `text`, so its last word and the icon stay on one line.
  Selecting it copies the value and shows Copied beside it for 2 seconds, through the
  sarduty:copy handler in app.js. See /styles/copy-button.
  """
  use Phoenix.Component

  import Web.Components.A, only: [a: 1]
  import Web.Components.Core, only: [icon: 1]

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :value, :string, required: true, doc: "the text to copy"
  attr :label, :string, required: true, doc: "what it copies, for screen readers: Copy address"
  attr :text, :string, default: nil, doc: "the value as shown before the button"
  attr :href, :string, default: nil, doc: "makes the text a link, such as mailto:"

  @doc """
  The text, then the button. The text's last word and the button never break apart,
  since browsers may wrap before a button even with no space between.
  """
  def copy_button(%{value: nil} = assigns), do: text_or_link(assigns)

  def copy_button(assigns) do
    {head, tail} = split_last_word(assigns)
    assigns = assign(assigns, head: head, tail: tail)

    ~H"""
    {@head}<span class="copy-tail"><.text_or_link text={@tail} href={@href} /><button
      id={@id}
      type="button"
      class="copy-button"
      value={@value}
      aria-label={@label}
      title={@label}
      phx-click={JS.dispatch("sarduty:copy", detail: %{status: "##{@id}-status"})}
    ><.icon name="copy" size={:sm} /></button></span><span
      id={"#{@id}-status"}
      class="copy-status"
      aria-live="polite"
    ></span>
    """
  end

  # A link stays whole, so its text is never split.
  defp split_last_word(%{text: nil}), do: {"", nil}
  defp split_last_word(%{text: text, href: href}) when is_binary(href), do: {"", text}

  defp split_last_word(%{text: text}) do
    case Regex.run(~r/^(.*\s)(\S+)\s*$/s, text, capture: :all_but_first) do
      [head, tail] -> {head, tail}
      nil -> {"", text}
    end
  end

  defp text_or_link(%{href: href} = assigns) when is_binary(href),
    do: ~H|<.a href={@href}>{@text}</.a>|

  defp text_or_link(assigns), do: ~H"{@text}"

  attr :id, :string, required: true, doc: "the block's id; its button is <id>-copy"
  attr :value, :string, required: true
  attr :label, :string, required: true, doc: "what it copies: Copy token"

  @doc "A code block with a copy button in its top-right corner."
  def copy_code_block(assigns) do
    ~H"""
    <div class="code-block-copy">
      <pre id={@id} class="code-block">{@value}</pre>
      <.copy_button id={"#{@id}-copy"} value={@value} label={@label} />
    </div>
    """
  end
end
