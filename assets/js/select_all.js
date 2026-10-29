// The checkbox in a table's header that checks or unchecks every checkbox in its column.
// It shows the mixed state when only some are checked. The click lands before the input
// event, so the form's phx-change sends the rows already changed. A box marked
// data-select-all="skip", such as a team admin's own chore (#697), is never checked by it
// and doesn't count toward its state, but clearing all clears it too.
export const SelectAll = {
  mounted() {
    this.table = this.el.closest("table")
    this.el.addEventListener("click", () => {
      const boxes = [...this.boxes(true)]
      for (const box of boxes) box.checked = this.el.checked && box.dataset.selectAll !== "skip"
      // Boxes that join a form outside the table (form="…") need the event from one of
      // them, since this box's own event reaches no form (#547).
      if (boxes[0] && boxes[0].form && boxes[0].form !== this.el.form) {
        boxes[0].dispatchEvent(new Event("input", {bubbles: true}))
      }
    })
    this.table.addEventListener("change", () => this.sync())
    // A LiveView patch can replace rows or change which are checked.
    this.observer = new MutationObserver(() => this.sync())
    this.observer.observe(this.table.tBodies[0], {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["checked"],
    })
    this.sync()
  },
  updated() {
    this.sync()
  },
  destroyed() {
    this.observer.disconnect()
  },
  boxes(withSkipped = false) {
    const column = this.el.closest("th").cellIndex + 1
    const skip = withSkipped ? "" : ":not([data-select-all=skip])"
    return this.table.querySelectorAll(
      `tbody > tr > td:nth-child(${column}) input[type=checkbox]:not(:disabled)${skip}`,
    )
  },
  sync() {
    const boxes = [...this.boxes()]
    const checked = boxes.filter(box => box.checked).length
    this.el.disabled = boxes.length === 0
    this.el.checked = boxes.length > 0 && checked === boxes.length
    this.el.indeterminate = checked > 0 && checked < boxes.length
  },
}
