// The Try a demo banner (#857): Show less folds it to one row and Show more opens it,
// remembered in this browser. The class goes through this.js(), so a LiveView patch
// keeps it. It starts open, so a first visit reads what a demo is.
const KEY = "demo-banner"

export const DemoBanner = {
  mounted() {
    if (this.stored() === "collapsed") this.js().addClass(this.el, "is-collapsed")

    this.el.addEventListener("click", (event) => {
      if (!event.target.closest("[data-demo-toggle]")) return
      const collapse = !this.el.classList.contains("is-collapsed")
      if (collapse) this.js().addClass(this.el, "is-collapsed")
      else this.js().removeClass(this.el, "is-collapsed")
      this.store(collapse ? "collapsed" : "open")
      this.el.querySelector(collapse ? "#demo-banner-expand" : "#demo-banner-collapse")?.focus()
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
      // Private browsing can refuse storage; the banner opens again next time.
    }
  },
}
