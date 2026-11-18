// "Not saved yet" beside an editor's Save (Web.Components.Unsaved). Once a draft keeps
// the changes (#1089), leaving loses nothing, so it asks only while something isn't
// kept: changes with no draft, an ask AI is still answering, or typing the server
// hasn't kept yet. data-rev goes up each time the server keeps a change, so typing
// counts until the next one. A reload or closing the tab asks through the browser's
// own question, and a link in the app through a confirm. Save and links marked
// data-leave-ok, such as Cancel, go without asking.
export const Unsaved = {
  mounted() {
    this.rev = this.el.dataset.rev
    this.typing = false
    const editor = this.el.closest(".ai-editor") || document.body

    this.question = () => {
      const data = this.el.dataset
      if (data.saving === "true") return "Leave now? AI is still answering. Its answer will be lost."
      if (data.unsaved === "true" && data.kept !== "true")
        return "Leave without saving? Your changes will be lost."
      if (this.typing) return "Leave now? Your latest change is not kept yet."
      return null
    }

    // Typing in the page, but not in the box an ask is written in.
    this.input = event => {
      if (!editor.contains(event.target) || event.target.closest(".ai-writing-form")) return
      this.typing = true
    }

    this.beforeUnload = event => {
      if (!this.question()) return
      event.preventDefault()
      event.returnValue = ""
    }

    this.click = event => {
      const question = this.question()
      if (!question) return
      const link = event.target.closest("a[href]")
      if (!link || link.closest("[data-leave-ok]") || link.target === "_blank") return
      if (link.getAttribute("href").startsWith("#")) return
      if (!window.confirm(question)) {
        event.preventDefault()
        event.stopImmediatePropagation()
      }
    }

    document.addEventListener("input", this.input, true)
    window.addEventListener("beforeunload", this.beforeUnload)
    document.addEventListener("click", this.click, true)
  },
  updated() {
    if (this.el.dataset.rev === this.rev) return
    this.rev = this.el.dataset.rev
    this.typing = false
  },
  destroyed() {
    document.removeEventListener("input", this.input, true)
    window.removeEventListener("beforeunload", this.beforeUnload)
    document.removeEventListener("click", this.click, true)
  },
}
