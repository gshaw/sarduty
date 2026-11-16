// "Not saved yet" beside an editor's Save (Web.Components.Unsaved). While it shows,
// leaving asks first: a reload or closing the tab through the browser's own question,
// and a link in the app through a confirm. Save and links marked data-leave-ok, such
// as Cancel, go without asking.
export const Unsaved = {
  mounted() {
    this.unsaved = () => this.el.dataset.unsaved === "true"

    this.beforeUnload = event => {
      if (!this.unsaved()) return
      event.preventDefault()
      event.returnValue = ""
    }

    this.click = event => {
      if (!this.unsaved()) return
      const link = event.target.closest("a[href]")
      if (!link || link.closest("[data-leave-ok]") || link.target === "_blank") return
      if (link.getAttribute("href").startsWith("#")) return
      if (!window.confirm("Leave without saving? Your changes will be lost.")) {
        event.preventDefault()
        event.stopImmediatePropagation()
      }
    }

    window.addEventListener("beforeunload", this.beforeUnload)
    document.addEventListener("click", this.click, true)
  },
  destroyed() {
    window.removeEventListener("beforeunload", this.beforeUnload)
    document.removeEventListener("click", this.click, true)
  },
}
