// The report editor's field buttons (#768): a click puts the field's name in the query
// where the cursor is, then sends the query's input event so the rows run again.
export const InsertField = {
  mounted() {
    this.el.addEventListener("click", (event) => {
      const button = event.target.closest("[data-field]")
      const box = document.getElementById(this.el.dataset.target)
      if (!button || !box) return
      box.setRangeText(button.dataset.field, box.selectionStart, box.selectionEnd, "end")
      box.focus()
      box.dispatchEvent(new Event("input", {bubbles: true}))
    })
  },
}
