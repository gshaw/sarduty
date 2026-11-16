// AI writing's column from 1024px (Web.Components.AIWriting): it fills the window from
// where it starts down to the Save bar, so the box stays in view, and as the page
// scrolls and it sticks under the site bar it grows to fill the rest. Its conversation
// scrolls on its own, and goes to the newest reply when an ask starts or ends.
export const AIPanel = {
  mounted() {
    this.wide = window.matchMedia("(min-width: 1024px)")
    this.size = () => this.fit()
    window.addEventListener("scroll", this.size, {passive: true})
    window.addEventListener("resize", this.size)
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
  },
  fit() {
    if (!this.wide.matches) {
      this.el.style.height = ""
      return
    }
    const bar = document.querySelector(".ai-bar")
    const below = bar ? bar.offsetHeight : 0
    const top = this.el.getBoundingClientRect().top
    this.el.style.height = `${Math.max(window.innerHeight - top - below - 16, 240)}px`
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
