// Reads a member card's QR code with the phone's camera on /verify and sends the text
// to the LiveView, which takes the code out of it. It never follows a link from a card.
// With data-reader="barcode", as on the equipment pages, it reads an item's barcode
// instead: Code 128, Code 39, UPC and EAN, and QR codes.
// With data-continuous, as on the door's attendance page, it keeps scanning after a read
// and skips the same card for a few seconds, so one card held up isn't recorded twice.
// With data-override-input, each read also sends that input's value, so the time box on
// the door's page counts even if the phone never sent a change for it.
// The scanning flag goes on the [data-scan-state] element inside the hook. LiveView
// patches the data attributes of a phx-update="ignore" container, so a flag on the
// container itself is wiped by the next render while the camera keeps running.
// The camera stops when the page goes to the background. Back on the page, the tap on
// Scan restarts it, and an iPhone needs that tap before a scan can make a sound.
// Switch camera, shown when the device has more than one, swaps the back and front
// cameras. The front camera serves an iPad kiosk facing the members (#248). The choice
// is remembered on the device, and the front camera's picture is mirrored like a mirror.
const PAUSE_MS = 1500
const SAME_CARD_MS = 5000

// Each reader is its own chunk, so a page downloads only the one it uses. A reader takes
// the camera's picture and answers the text it found, or nothing.
// cspell:ignore jsqr -- the vendored jsQR library file
const READERS = {
  qr: () =>
    import("../vendor/jsqr").then(({default: jsQR}) => ({data, width, height}) => jsQR(data, width, height)?.data),
  barcode: () => import("./barcode_reader").then(module => module.read),
}

// Both readers take the camera's default picture. Asking an iPhone for 1280×720 started
// the camera but left the picture blank (2026-10-11).
const FACING_KEY = "sarduty:scan-facing"
const FACING = ["environment", "user"]

function savedFacing() {
  const facing = localStorage.getItem(FACING_KEY)
  return FACING.includes(facing) ? facing : "environment"
}

export const QRScanner = {
  mounted() {
    // Start loading the reader now so a tap on Scan doesn't wait for it.
    this.reader = this.el.dataset.reader in READERS ? this.el.dataset.reader : "qr"
    this.decoder = READERS[this.reader]()
    this.video = this.el.querySelector("video")
    this.canvas = document.createElement("canvas")
    this.state = this.el.querySelector("[data-scan-state]")
    this.el.querySelector("[data-scan-start]").addEventListener("click", () => this.start())
    this.el.querySelector("[data-scan-stop]").addEventListener("click", () => this.stop())
    this.flip = this.el.querySelector("[data-scan-flip]")
    this.flip.querySelector("button").addEventListener("click", () => this.switchCamera())
    this.onVisibility = () => document.hidden && this.stop()
    document.addEventListener("visibilitychange", this.onVisibility)
  },

  destroyed() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.stop()
  },

  // A second tap while the reader loads would open the camera twice, and an iPhone
  // blanks the first camera when a second one opens.
  async start() {
    if (this.starting || this.stream) return
    this.starting = true
    try {
      this.decode = await this.decoder
      this.facing = savedFacing()
      this.stream = await navigator.mediaDevices.getUserMedia({video: {facingMode: this.facing}})
    } catch (_error) {
      this.pushEvent("scan_failed", {})
      return
    } finally {
      this.starting = false
    }
    this.video.srcObject = this.stream
    this.video.style.transform = this.facing === "user" ? "scaleX(-1)" : ""
    await this.video.play()
    this.state.dataset.scanning = "true"
    this.showFlip()
    this.tick()
  },

  // Cameras are listed only once the page may use one, so this runs after the first.
  async showFlip() {
    const devices = await navigator.mediaDevices.enumerateDevices().catch(() => [])
    this.flip.hidden = devices.filter(device => device.kind === "videoinput").length < 2
  },

  // The old camera stops first, since an iPhone blanks a camera when a second one opens.
  switchCamera() {
    localStorage.setItem(FACING_KEY, this.facing === "user" ? "environment" : "user")
    this.stop()
    this.start()
  },

  stop() {
    cancelAnimationFrame(this.frame)
    clearTimeout(this.frame)
    this.stream?.getTracks().forEach(track => track.stop())
    this.stream = null
    delete this.state.dataset.scanning
  },

  pushScanned(code) {
    const input = document.getElementById(this.el.dataset.overrideInput || "")
    this.pushEvent("scanned", input ? {code, override: input.value} : {code})
  },

  // The barcode reader answers later, so a tick checks the camera is still the one it
  // started with. Otherwise a Stop and Scan during a read would run two loops.
  async tick() {
    const stream = this.stream
    if (!stream) return
    const {videoWidth: width, videoHeight: height} = this.video
    if (width > 0) {
      this.canvas.width = width
      this.canvas.height = height
      const context = this.canvas.getContext("2d", {willReadFrequently: true})
      context.drawImage(this.video, 0, 0, width, height)
      let found
      try {
        found = await this.decode(context.getImageData(0, 0, width, height))
      } catch (_error) {
        // The barcode reader's .wasm file did not load.
        this.stop()
        this.pushEvent("scan_failed", {})
        return
      }
      if (this.stream !== stream) return
      if (found) {
        if (!("continuous" in this.el.dataset)) {
          this.stop()
          this.pushScanned(found)
          return
        }
        const now = Date.now()
        if (found !== this.lastRead || now - this.lastReadAt > SAME_CARD_MS) {
          this.pushScanned(found)
          this.lastRead = found
          this.lastReadAt = now
          this.frame = setTimeout(() => this.tick(), PAUSE_MS)
          return
        }
        this.lastReadAt = now
      }
    }
    this.frame = requestAnimationFrame(() => this.tick())
  },
}
