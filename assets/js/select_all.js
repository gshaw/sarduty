// The checkbox in a table's header that checks or unchecks every checkbox in its column.
// It shows the mixed state when only some are checked. The click lands before the input
// event, so the form's phx-change sends the rows already changed.
export const SelectAll = {
  mounted() {
    this.table = this.el.closest("table")
    this.el.addEventListener("click", () => {
      for (const box of this.boxes()) box.checked = this.el.checked
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
  boxes() {
    const column = this.el.closest("th").cellIndex + 1
    return this.table.querySelectorAll(
      `tbody > tr > td:nth-child(${column}) input[type=checkbox]:not(:disabled)`,
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
