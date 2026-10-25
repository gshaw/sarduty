// A file drop (<.file_drop>): LiveView takes a dropped file itself, through
// phx-drop-target. This adds paste, for a screenshot or a file copied in Finder: a file
// pasted anywhere on the page goes to the drop's upload, as a dropped one would. Only on a
// page with one drop, so a paste never guesses which upload it is for.
export const FileDrop = {
  mounted() {
    this.onPaste = event => {
      const files = [...(event.clipboardData?.files || [])]
      if (files.length === 0) return
      if (document.querySelectorAll("[phx-hook=FileDrop]").length > 1) return
      event.preventDefault()
      this.upload(this.el.dataset.upload, files.slice(0, 1))
    }
    window.addEventListener("paste", this.onPaste)
  },

  destroyed() {
    window.removeEventListener("paste", this.onPaste)
  },
}
