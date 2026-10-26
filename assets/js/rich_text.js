// The rich text input (<.input type="rich_text">, #599): Trix, loaded only on a page that
// has one. Trix holds what its toolbar makes: bold, italics, links, and lists. Headings,
// quotes, code, strike, and files are taken out of it, so a paste can't bring them in
// either. The server cleans the HTML again (Service.DescriptionHTML).
let loading

function loadTrix() {
  loading ||= import("../vendor/trix.js").then(({default: Trix}) => {
    // Trix defines its elements a tick after it loads, so this runs first.
    for (const name of ["heading1", "quote", "code"]) delete Trix.config.blockAttributes[name]
    delete Trix.config.textAttributes.strike
  })
  return loading
}

const webAddress = /^https?:\/\/\S+$/

export const RichText = {
  mounted() {
    const editorEl = this.el.querySelector("trix-editor")
    const dialog = this.el.querySelector("[data-trix-dialog=href]")

    this.el.addEventListener("trix-file-accept", event => event.preventDefault())
    this.el.addEventListener("trix-attachment-add", event => event.attachment.remove())

    // A web address pasted over selected text links the text, as in Docs or Slack.
    editorEl.addEventListener("paste", event => {
      const url = event.clipboardData?.getData("text/plain").trim()
      const [start, end] = editorEl.editor?.getSelectedRange() ?? [0, 0]
      if (start === end || !webAddress.test(url ?? "")) return
      event.preventDefault()
      event.stopImmediatePropagation()
      editorEl.editor.activateAttribute("href", url)
    }, true)

    this.el.addEventListener("trix-toolbar-dialog-show", () => {
      const editor = editorEl.editor
      dialog.classList.toggle("is-editing-link", editor.attributeIsActive("href"))
      this.placeDialog(editorEl, dialog)
    })

    // Trix closes the box on Escape and on its own buttons; a click outside closes it too.
    // The toolbar's own clicks are left to Trix, which toggles the box from the link button.
    const toolbar = this.el.querySelector("trix-toolbar")
    this.onMouseDown = event => {
      if (dialog.hasAttribute("data-trix-active") && !toolbar.contains(event.target)) {
        editorEl.editorController?.toolbarController.hideDialog()
      }
    }
    document.addEventListener("mousedown", this.onMouseDown)

    loadTrix()
  },

  destroyed() {
    document.removeEventListener("mousedown", this.onMouseDown)
  },

  // Under the selection's first line, kept inside the editor's box.
  placeDialog(editorEl, dialog) {
    const box = this.el.getBoundingClientRect()
    const editorBox = editorEl.getBoundingClientRect()
    const [start] = editorEl.editor.getSelectedRange()
    const rect = editorEl.editor.getClientRectAtPosition(start) ??
      editorEl.editor.getClientRectAtPosition(Math.max(start - 1, 0))
    const top = (rect ? rect.bottom : editorBox.top) - box.top + 4
    const left = (rect ? rect.left : editorBox.left) - box.left
    const maxLeft = box.width - dialog.offsetWidth - 8
    dialog.style.top = `${top}px`
    dialog.style.left = `${Math.max(8, Math.min(left, maxLeft))}px`
  },
}
