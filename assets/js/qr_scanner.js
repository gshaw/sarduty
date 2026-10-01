// Reads a member card's QR code with the phone's camera on /verify and sends the text
// to the LiveView, which takes the code out of it. It never follows a link from a card.
export const QRScanner = {
  mounted() {
    // jsQR is its own chunk, so only this page downloads it. Start now so a tap
    // on Scan doesn't wait for it.
    // cspell:ignore jsqr -- the vendored jsQR library file
    this.decoder = import("../vendor/jsqr").then(module => module.default)
    this.video = this.el.querySelector("video")
    this.canvas = document.createElement("canvas")
    this.el.querySelector("[data-scan-start]").addEventListener("click", () => this.start())
    this.el.querySelector("[data-scan-stop]").addEventListener("click", () => this.stop())
  },

  destroyed() {
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
    this.el.dataset.scanning = "true"
    this.tick()
  },

  stop() {
    cancelAnimationFrame(this.frame)
    this.stream?.getTracks().forEach(track => track.stop())
    this.stream = null
    delete this.el.dataset.scanning
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
        this.stop()
        this.pushEvent("scanned", {code: found.data})
        return
      }
    }
    this.frame = requestAnimationFrame(() => this.tick())
  },
}
