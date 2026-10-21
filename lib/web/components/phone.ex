defmodule Web.Components.Phone do
  @moduledoc """
  A member's phone number to read, and Call and Text buttons for it on touch screens
  (#300). A desktop gets the number alone: tel: and sms: links there often open nothing.
  See /styles/call-and-text.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [button: 1]

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
