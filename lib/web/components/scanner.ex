defmodule Web.Components.Scanner do
  @moduledoc """
  The phone camera's QR code scanner: a big button that starts it, the camera's picture
  while it scans, with Stop scanning and Switch camera under it, and the Sound switch. The
  QRScanner hook (assets/js/qr_scanner.js) sends each read to the LiveView as a "scanned"
  event. With `reader={:barcode}` it reads
  equipment barcodes instead. Each start swaps the video below for a new one the hook
  makes, which an iPhone draws. See /styles/qr-scanner.

  The picture is 4:3 on a phone and a square from an iPad up, never taller than 45% of
  the screen (#752). A QR reader draws a square to aim at and reads only around it. The
  `result` slot draws over the picture while it scans, as Take attendance shows each read.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [button: 1, switch: 1]

  attr :id, :string, default: "scanner"
  attr :label, :string, required: true, doc: "the start button, such as Scan ID cards"
  attr :variant, :atom, default: :primary, values: [:primary, :success]
  attr :reader, :atom, default: :qr, values: [:qr, :barcode], doc: "QR codes, or barcodes too"

  attr :hint, :string,
    default: nil,
    doc: "under the aim square, such as Hold the ID card in the square"

  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(data-continuous data-override-input),
    doc: "data-continuous keeps scanning after a read; data-override-input names a time box"

  slot :result, doc: "what the last read did, drawn over the picture" do
    attr :kind, :atom, required: true, values: [:success, :info, :danger]
  end

  def qr_scanner(assigns) do
    ~H"""
    <div id={@id} phx-hook="QRScanner" data-reader={@reader} class={["scanner", @class]} {@rest}>
      <div id={"#{@id}-camera"} phx-update="ignore">
        <div data-scan-state class="group">
          <div class="scanner-picture hidden group-data-scanning:block">
            <video class="scanner-video" playsinline muted></video>
            <div :if={@reader == :qr} class="scanner-aim" data-scan-aim></div>
            <p :if={@hint} class="scanner-hint">{@hint}</p>
          </div>
          <div class="group-data-scanning:hidden">
            <.button
              type="button"
              variant={@variant}
              size={:lg}
              icon="scan-line"
              class="w-full"
              data-scan-start
            >
              {@label}
            </.button>
          </div>
          <div class="hidden group-data-scanning:flex gap-2 mt-2">
            <.button type="button" class="flex-1" data-scan-stop>Stop scanning</.button>
            <div class="flex-1" data-scan-flip hidden>
              <.button type="button" class="w-full">Switch camera</.button>
            </div>
          </div>
        </div>
      </div>
      <div
        :for={result <- @result}
        id={"#{@id}-result"}
        class={["scanner-result", "scanner-result-#{result.kind}"]}
        role="status"
      >
        {render_slot(result)}
      </div>
      <.switch
        id="sound-switch"
        label="Sound"
        compact
        class="mt-2"
        checked
        phx-hook="SoundSwitch"
        phx-update="ignore"
      />
    </div>
    """
  end
end
