// Rows people put in order (Web.Components.DragList, /styles/drag-list). The grip handle
// drags its row with a mouse, a finger, or a pen: pointer events, with touch-action: none
// on the handle so an iPad doesn't scroll instead. On the keyboard the handle moves its
// row with the up and down arrows, and Move up and Move down buttons do the same. Each
// move happens here at once, then sends the list's event with every row's key in the new
// order, and the LiveView renders the list in that order.
export const DragList = {
  mounted() {
    this.el.addEventListener("pointerdown", event => this.start(event))
    this.el.addEventListener("keydown", event => this.key(event))
    this.el.addEventListener("click", event => this.click(event))
  },

  // A patch can move or redraw the row that had focus. Put it back where the person was.
  updated() {
    if (!this.focusAt || this.el.contains(document.activeElement)) return
    const row = this.rows()[this.focusAt.index]
    row?.querySelector(this.focusAt.selector)?.focus()
  },

  rows() {
    return [...this.el.querySelectorAll(":scope .drag-rows > .drag-row")]
  },

  key(event) {
    const handle = event.target.closest("[data-drag-handle]")
    if (!handle || !["ArrowUp", "ArrowDown"].includes(event.key)) return
    event.preventDefault()
    this.move(handle.closest(".drag-row"), event.key === "ArrowUp" ? -1 : 1, "[data-drag-handle]")
  },

  click(event) {
    const button = event.target.closest("[data-move]")
    if (!button || button.disabled) return
    const up = button.dataset.move === "up"
    const row = button.closest(".drag-row")
    this.move(row, up ? -1 : 1, `[data-move=${up ? "up" : "down"}]`)
    // At the top or the bottom, the button that still works takes focus.
    if (button.disabled) row.querySelector(`[data-move=${up ? "down" : "up"}]`)?.focus()
  },

  // Moves a row one place up (-1) or down (1), keeps focus on the control that moved it,
  // and sends the order.
  move(row, step, selector) {
    const rows = this.rows()
    const index = rows.indexOf(row)
    const target = index + step
    if (target < 0 || target >= rows.length) return
    // The neighbour moves rather than the row, so the row keeps focus.
    if (step < 0) row.after(rows[target])
    else row.before(rows[target])
    this.focusAt = {index: target, selector}
    row.querySelector(selector)?.focus()
    this.changed(row)
  },

  start(event) {
    const handle = event.target.closest("[data-drag-handle]")
    if (!handle || (event.pointerType === "mouse" && event.button !== 0)) return
    event.preventDefault()
    const row = handle.closest(".drag-row")
    const before = this.keys()
    const grab = event.clientY - row.getBoundingClientRect().top
    handle.setPointerCapture(event.pointerId)
    row.classList.add("dragging")
    this.el.classList.add("is-dragging")
    this.focusAt = null

    const follow = moveEvent => {
      this.scrollNear(moveEvent.clientY)
      this.place(row, moveEvent.clientY - grab)
    }
    const stop = () => {
      window.removeEventListener("pointermove", follow)
      window.removeEventListener("pointerup", stop)
      window.removeEventListener("pointercancel", stop)
      row.style.transform = ""
      row.classList.remove("dragging")
      this.el.classList.remove("is-dragging")
      if (this.keys().join() !== before.join()) this.changed(row)
    }
    window.addEventListener("pointermove", follow)
    window.addEventListener("pointerup", stop)
    window.addEventListener("pointercancel", stop)
  },

  // Moves each neighbour whose middle the dragged row has crossed to its other side, then
  // shifts the row so it stays under the pointer. The neighbours move, not the row, so
  // the handle keeps the pointer.
  place(row, top) {
    row.style.transform = ""
    for (;;) {
      const prev = row.previousElementSibling
      const next = row.nextElementSibling
      const height = row.offsetHeight
      if (prev && top < middle(prev)) row.after(prev)
      else if (next && top + height > middle(next)) row.before(next)
      else break
    }
    const rows = this.rows()
    const first = rows[0].getBoundingClientRect().top
    const last = rows[rows.length - 1].getBoundingClientRect().bottom - row.offsetHeight
    const clamped = Math.min(Math.max(top, first), last)
    row.style.transform = `translateY(${clamped - row.getBoundingClientRect().top}px)`
  },

  // Near the top or bottom of the window, the page scrolls so a long list can be dragged.
  scrollNear(y) {
    const edge = 48
    if (y < edge) window.scrollBy(0, -8)
    else if (y > window.innerHeight - edge) window.scrollBy(0, 8)
  },

  keys() {
    return this.rows().map(row => row.dataset.key)
  },

  // Greys Move up on the first row and Move down on the last, says where the row went,
  // and sends the order.
  changed(row) {
    const rows = this.rows()
    rows.forEach((each, i) => {
      const up = each.querySelector("[data-move=up]")
      const down = each.querySelector("[data-move=down]")
      if (up) up.disabled = i === 0
      if (down) down.disabled = i === rows.length - 1
    })
    const status = this.el.querySelector("[data-drag-status]")
    if (status) status.textContent = `${row.dataset.label}, ${rows.indexOf(row) + 1} of ${rows.length}`
    this.pushEvent(this.el.dataset.event, {keys: this.keys()})
  },
}

function middle(element) {
  const box = element.getBoundingClientRect()
  return box.top + box.height / 2
}
