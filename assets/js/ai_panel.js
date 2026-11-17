// AI writing's column from 1024px (Web.Components.AIWriting): it fills the window from
// where it starts down to the Save bar, so the box stays in view, and as the page
// scrolls and it sticks under the site bar it grows to fill the rest. Its conversation
// scrolls on its own, and goes to the newest reply when an ask starts or ends.
//
// It never grows past the head and main part, or the page would grow with each scroll
// and the report scroll away. Its least is what fills the window at the top of the
// page, which doesn't change as the page scrolls.
export const AIPanel = {
  mounted() {
    this.wide = window.matchMedia("(min-width: 1024px)")
    this.size = () => this.fit()
    window.addEventListener("scroll", this.size, {passive: true})
    window.addEventListener("resize", this.size)
    this.grid = this.el.parentElement
    this.main = this.grid.querySelector(".ai-main")
    this.observer = new ResizeObserver(this.size)
    if (this.main) this.observer.observe(this.main)
    this.asks = this.count()
    this.fit()
    this.toNewest()
  },
  updated() {
    this.fit()
    const asks = this.count()
    if (asks !== this.asks) this.toNewest()
    this.asks = asks
  },
  destroyed() {
    window.removeEventListener("scroll", this.size)
    window.removeEventListener("resize", this.size)
    this.observer.disconnect()
  },
  fit() {
    if (!this.wide.matches) {
      this.el.style.height = ""
      return
    }
    const bar = document.querySelector(".ai-bar")
    const below = (bar ? bar.offsetHeight : 0) + 16
    const stuck = parseFloat(getComputedStyle(this.el).top) || 0
    const gridTop = this.grid.getBoundingClientRect().top
    const view = window.innerHeight - Math.max(this.el.getBoundingClientRect().top, stuck) - below
    const content = this.main ? this.main.getBoundingClientRect().bottom - gridTop : view
    const least = window.innerHeight - (gridTop + window.scrollY) - below
    this.el.style.height = `${Math.max(Math.min(view, content), least, 240)}px`
  },
  // Asks and the running one, so a new ask or its answer scrolls to the newest.
  count() {
    return this.el.querySelectorAll(".ai-you, .ai-reply, .ai-step").length
  },
  toNewest() {
    const scroll = this.el.querySelector(".ai-scroll")
    if (scroll) scroll.scrollTop = scroll.scrollHeight
  },
}
