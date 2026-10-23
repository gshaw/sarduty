// The door page's name box, which a plug-in barcode scanner types ID cards into (#484).
// On a laptop it takes the cursor when the page opens, and back after Arriving or
// Leaving, so the first scan goes straight in. Not on a touch screen: iOS would open
// its keyboard over the page, and ignores focus a page sets without a tap anyway.
// After a card is recorded it empties itself and keeps the cursor for the next one;
// the server can't, since LiveView leaves a focused box's value alone.
export const ScannerInput = {
  mounted() {
    this.focusOnLaptop()
    this.handleEvent("clear-search", () => {
      this.el.value = ""
    })
    this.onClick = (event) => {
      if (event.target.closest("[data-return-focus]")) this.focusOnLaptop()
    }
    document.addEventListener("click", this.onClick)
  },
  destroyed() {
    document.removeEventListener("click", this.onClick)
  },
  focusOnLaptop() {
    if (window.matchMedia("(pointer: fine)").matches) this.el.focus()
  },
}
