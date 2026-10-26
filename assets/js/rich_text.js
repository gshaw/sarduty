// The rich text input (<.input type="rich_text">, #598): Trix, loaded only on a page that
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

export const RichText = {
  mounted() {
    this.el.addEventListener("trix-file-accept", event => event.preventDefault())
    this.el.addEventListener("trix-attachment-add", event => event.attachment.remove())
    loadTrix()
  },
}
