// AI writing's column (Web.Components.AIWriting). Its conversation is newest first under
// the box and scrolls on its own from 1024px; when an ask starts or ends it goes back to
// the top, so the newest shows.
export const AIPanel = {
  mounted() {
    this.asks = this.count()
  },
  updated() {
    const asks = this.count()
    if (asks !== this.asks) {
      const scroll = this.el.querySelector(".ai-scroll")
      if (scroll) scroll.scrollTop = 0
    }
    this.asks = asks
  },
  // Asks and the running one.
  count() {
    return this.el.querySelectorAll(".ai-you, .ai-reply, .ai-step").length
  },
}
