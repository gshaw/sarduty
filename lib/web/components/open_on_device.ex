defmodule Web.Components.OpenOnDevice do
  @moduledoc """
  A sidebar with a QR code of a page, so someone at a computer opens it on the phone or
  iPad that does the task: Take attendance on the door's iPad (#475), an ID card's page on
  the member's phone (#952). Hidden on a touch screen, which is the device already. It
  sits beside the page's main column, `md:w-2/3` and `md:w-1/3`. See
  /styles/open-on-device.
  """
  use Web, :function_component

  attr :id, :string, required: true
  attr :heading, :string, required: true, doc: "where it opens: Open on your phone"
  attr :url, :string, required: true, doc: "the page the QR code opens"
  slot :inner_block, required: true, doc: "what to do with the code, then anything more"

  attr :class, :any,
    default: "md:w-1/3",
    doc: "its width beside the main column; nil in a sidebar column with more under it"

  def open_on_device(assigns) do
    assigns = assign(assigns, :qr_code, qr_code(assigns.url))

    ~H"""
    <aside id={@id} class={[@class, "mt-8 pointer-coarse:hidden"]}>
      <h2 class="heading">{@heading}</h2>
      <div class="qr-code mb-4" aria-hidden="true">{Phoenix.HTML.raw(@qr_code)}</div>
      {render_slot(@inner_block)}
    </aside>
    """
  end

  defp qr_code(url), do: url |> EQRCode.encode(:m) |> EQRCode.svg(viewbox: true, color: "#000")
end
