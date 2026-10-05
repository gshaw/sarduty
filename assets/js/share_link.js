// A button that opens the device's share sheet with its data-url. It stays hidden where
// the browser has no share sheet, which is most desktop browsers.
export const ShareLink = {
  mounted() {
    this.show()
    this.el.addEventListener("click", () => {
      navigator.share({url: this.el.dataset.url}).catch(() => {})
    })
  },
  updated() {
    this.show()
  },
  show() {
    if (navigator.share) this.el.hidden = false
  },
}
