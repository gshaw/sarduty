defmodule Web.Components.Phone do
  @moduledoc """
  A phone number to reach someone by, with a copy button, and Call and Text buttons for
  it on touch screens (#300). A desktop gets no buttons: tel: and sms: links there often
  open nothing. See /styles/phone.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [button: 1]
  import Web.Components.CopyButton, only: [copy_button: 1]

  attr :id, :string,
    required: true,
    doc: "the copy button's is <id>-copy, the buttons' <id>-call and <id>-text"

  attr :phone, :string, default: nil, doc: "the number as D4H has it"
  attr :call_and_text, :boolean, default: false, doc: "Call and Text buttons under it"
  attr :missing, :string, default: nil, doc: "shown, as a hint, when there's no number"
  attr :class, :any, default: nil, doc: "for the Call and Text buttons"

  attr :touch_only, :boolean,
    default: true,
    doc: "false shows the buttons everywhere, for /styles"

  def phone(assigns) do
    assigns = assign(assigns, :shown, Service.Phone.format(assigns.phone))

    ~H"""
    <%= if @shown do %>
      <.copy_button id={"#{@id}-copy"} text={@shown} value={@shown} label="Copy phone number" />
      <.call_and_text
        :if={@call_and_text}
        id={@id}
        phone={@phone}
        touch_only={@touch_only}
        class={@class}
      />
    <% else %>
      <span :if={@missing} class="hint">{@missing}</span>
    <% end %>
    """
  end

  attr :id, :string, required: true, doc: "the buttons' ids are <id>-call and <id>-text"
  attr :phone, :string, default: nil, doc: "the number as D4H has it"
  attr :touch_only, :boolean, default: true, doc: "false shows them everywhere, for /styles"
  attr :class, :any, default: nil

  def call_and_text(assigns) do
    assigns = assign(assigns, :dial, dial(assigns.phone))

    ~H"""
    <span
      :if={@dial}
      class={[if(@touch_only, do: "hidden pointer-coarse:flex", else: "flex"), "gap-2", @class]}
    >
      <.button id={"#{@id}-call"} size={:sm} href={"tel:#{@dial}"}>Call</.button>
      <%!-- Phoenix's link allows tel: but not sms:, so the scheme goes as a tuple. --%>
      <.button id={"#{@id}-text"} size={:sm} href={{:sms, @dial}}>Text</.button>
    </span>
    """
  end

  @doc "E.164 when D4H's number reads as one, so tel: and sms: links dial it. Nil for none."
  def dial(phone), do: Service.Phone.normalize(phone) || blank_to_nil(phone)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(text), do: if(String.trim(text) == "", do: nil, else: String.trim(text))
end
