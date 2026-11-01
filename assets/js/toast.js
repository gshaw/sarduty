// A result's toast fades after data-seconds: 6, or 10 with a subtitle. Errors have none
// and stay. The clock stops while the pointer, a finger, or focus is on the toast, or the
// page is hidden (another app or tab), and gives back at least 3 s. Fading runs
// data-dismiss, the same as ×, so the server clears the flash too and the next render
// can't bring the toast back.
const RESUME_MS = 3000

export const Toast = {
  mounted() {
    this.holds = new Set()
    const hold = (why) => () => { this.holds.add(why); this.pause() }
    const release = (why) => () => { this.holds.delete(why); this.resume() }
    this.el.addEventListener("pointerenter", hold("pointer"))
    this.el.addEventListener("pointerleave", release("pointer"))
    this.el.addEventListener("pointerdown", hold("press"))
    this.el.addEventListener("pointerup", release("press"))
    this.el.addEventListener("pointercancel", release("press"))
    this.el.addEventListener("focusin", hold("focus"))
    this.el.addEventListener("focusout", release("focus"))
    this.onVisibility = () => document.hidden ? hold("hidden")() : release("hidden")()
    document.addEventListener("visibilitychange", this.onVisibility)
    if (document.hidden) this.holds.add("hidden")
    this.start()
  },
  // A new message in the same toast starts its own clock.
  updated() {
    if (this.el.textContent !== this.text) this.start()
  },
  destroyed() {
    clearTimeout(this.timer)
    document.removeEventListener("visibilitychange", this.onVisibility)
  },
  start() {
    clearTimeout(this.timer)
    this.text = this.el.textContent
    const seconds = Number(this.el.dataset.seconds)
    this.left = seconds > 0 ? seconds * 1000 : null
    this.resume(true)
  },
  pause() {
    if (!this.timer) return
    clearTimeout(this.timer)
    this.timer = null
    this.left = Math.max(this.left - (Date.now() - this.since), 0)
  },
  resume(fresh = false) {
    if (this.left === null || this.timer || this.holds.size > 0) return
    if (!fresh) this.left = Math.max(this.left, RESUME_MS)
    this.since = Date.now()
    this.timer = setTimeout(() => this.liveSocket.execJS(this.el, this.el.dataset.dismiss), this.left)
  },
}
