// The report editor's help column (#784): Hide help and Show help, remembered in this
// browser. The class goes through this.js(), so a LiveView patch keeps it.
const KEY = "report-help"

export const HelpToggle = {
  mounted() {
    if (this.stored() === "hidden") this.js().addClass(this.el, "is-help-hidden")

    this.el.addEventListener("click", (event) => {
      const toggle = event.target.closest("[data-help]")
      if (!toggle) return
      event.preventDefault()
      const hide = toggle.dataset.help === "hide"
      if (hide) this.js().addClass(this.el, "is-help-hidden")
      else this.js().removeClass(this.el, "is-help-hidden")
      this.store(hide ? "hidden" : "shown")
      this.el.querySelector(`[data-help=${hide ? "show" : "hide"}]`)?.focus()
    })
  },

  stored() {
    try {
      return localStorage.getItem(KEY)
    } catch {
      return null
    }
  },

  store(value) {
    try {
      localStorage.setItem(KEY, value)
    } catch {
      // Private browsing can refuse storage; the column shows again next time.
    }
  },
}
