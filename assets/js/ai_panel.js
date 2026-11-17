// AI writing's column (Web.Components.AIWriting). Its conversation is oldest first above
// the box and, once the column is as tall as the window, scrolls on its own; it goes to
// the newest at the start and when an ask starts or ends.
export const AIPanel = {
  mounted() {
    this.asks = this.count()
    this.toNewest()
  },
  updated() {
    const asks = this.count()
    if (asks !== this.asks) this.toNewest()
    this.asks = asks
  },
  // Asks and the running one.
  count() {
    return this.el.querySelectorAll(".ai-you, .ai-reply, .ai-step").length
  },
  toNewest() {
    const scroll = this.el.querySelector(".ai-scroll")
    if (scroll) scroll.scrollTop = scroll.scrollHeight
  },
}
