// Reads a member card's QR code with the phone's camera on /verify and sends the text
// to the LiveView, which takes the code out of it. It never follows a link from a card.
// With data-continuous, as on the door's attendance page, it keeps scanning after a read
// and skips the same card for a few seconds, so one card held up isn't recorded twice.
// With data-override-input, each read also sends that input's value, so the time box on
// the door's page counts even if the phone never sent a change for it.
// The scanning flag goes on the [data-scan-state] element inside the hook. LiveView
// patches the data attributes of a phx-update="ignore" container, so a flag on the
// container itself is wiped by the next render while the camera keeps running.
// The camera stops when the page goes to the background. Back on the page, the tap on
// Scan restarts it, and an iPhone needs that tap before a scan can make a sound.
const PAUSE_MS = 1500
const SAME_CARD_MS = 5000

export const QRScanner = {
  mounted() {
    // jsQR is its own chunk, so only this page downloads it. Start now so a tap
    // on Scan doesn't wait for it.
    // cspell:ignore jsqr -- the vendored jsQR library file
    this.decoder = import("../vendor/jsqr").then(module => module.default)
    this.video = this.el.querySelector("video")
    this.canvas = document.createElement("canvas")
    this.state = this.el.querySelector("[data-scan-state]")
    this.el.querySelector("[data-scan-start]").addEventListener("click", () => this.start())
    this.el.querySelector("[data-scan-stop]").addEventListener("click", () => this.stop())
    this.onVisibility = () => document.hidden && this.stop()
    document.addEventListener("visibilitychange", this.onVisibility)
  },

  destroyed() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.stop()
  },

  async start() {
    try {
      this.decode = await this.decoder
      this.stream = await navigator.mediaDevices.getUserMedia({video: {facingMode: "environment"}})
    } catch (_error) {
      this.pushEvent("scan_failed", {})
      return
    }
    this.video.srcObject = this.stream
    await this.video.play()
    this.state.dataset.scanning = "true"
    this.tick()
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

  tick() {
    if (!this.stream) return
    const {videoWidth: width, videoHeight: height} = this.video
    if (width > 0) {
      this.canvas.width = width
      this.canvas.height = height
      const context = this.canvas.getContext("2d", {willReadFrequently: true})
      context.drawImage(this.video, 0, 0, width, height)
      const found = this.decode(context.getImageData(0, 0, width, height).data, width, height)
      if (found?.data) {
        if (!("continuous" in this.el.dataset)) {
          this.stop()
          this.pushScanned(found.data)
          return
        }
        const now = Date.now()
        if (found.data !== this.lastRead || now - this.lastReadAt > SAME_CARD_MS) {
          this.pushScanned(found.data)
          this.lastRead = found.data
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
