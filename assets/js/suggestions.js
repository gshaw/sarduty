// A text box with suggestions (<.input suggestions>). The x empties it and keeps focus, so
// the browser's list opens again; it fires the input event, so phx-change still runs. The
// box has no placeholder for CSS to test, so data-empty hides the x when there is no text.
export const Suggestions = {
  mounted() {
    this.input = this.el.querySelector("input")
    this.input.addEventListener("input", () => this.sync())
    const clear = this.el.querySelector(".combobox-clear")
    clear.addEventListener("mousedown", event => event.preventDefault())
    clear.addEventListener("click", () => {
      if (this.input.disabled || this.input.readOnly) return
      this.input.value = ""
      this.input.dispatchEvent(new Event("input", {bubbles: true}))
      this.input.focus()
    })
    this.sync()
  },

  updated() {
    this.sync()
  },

  sync() {
    this.el.toggleAttribute("data-empty", this.input.value === "")
  },
}
