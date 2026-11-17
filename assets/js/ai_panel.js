// AI writing's column (Web.Components.AIWriting), a chat: the conversation oldest first,
// then Try next and the box. From 1024px it grows with the conversation until it reaches
// the window's foot, from wherever it starts (beside the title at first, under the site
// bar once stuck); then the conversation scrolls on its own. Only its most is set, so it
// never makes the page longer than its content. Whenever the conversation grows or
// shrinks, it goes to the newest; the seconds ticking while AI thinks don't count.
export const AIPanel = {
  mounted() {
    this.wide = window.matchMedia("(min-width: 1024px)")
    this.fit = () => this.fitHeight()
    window.addEventListener("scroll", this.fit, {passive: true})
    window.addEventListener("resize", this.fit)
    this.height = -1
    this.observer = new MutationObserver(() => this.toNewest())
    this.observer.observe(this.el, {childList: true, subtree: true, characterData: true})
    this.fitHeight()
    this.toNewest()
  },
  updated() {
    this.fitHeight()
    this.toNewest()
  },
  destroyed() {
    window.removeEventListener("scroll", this.fit)
    window.removeEventListener("resize", this.fit)
    this.observer.disconnect()
  },
  fitHeight() {
    if (!this.wide.matches) {
      this.el.style.maxHeight = ""
      return
    }
    const stuck = parseFloat(getComputedStyle(this.el).top) || 0
    const top = Math.max(this.el.getBoundingClientRect().top, stuck)
    this.el.style.maxHeight = `${Math.max(window.innerHeight - top - 16, 240)}px`
  },
  toNewest() {
    const scroll = this.el.querySelector(".ai-scroll")
    if (!scroll || scroll.scrollHeight === this.height) return
    this.height = scroll.scrollHeight
    scroll.scrollTop = scroll.scrollHeight
  },
}
