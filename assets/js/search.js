// The top bar's search (#473). The server renders the results; this opens and closes the
// panel, moves through the results with the arrow keys, and opens one with Enter. Focus
// stays in the field and aria-activedescendant names the highlighted result, as in the
// WAI combobox pattern. Classes and attributes go through this.js(), so the server's
// renders keep them. "/" anywhere outside a field jumps to the search.
export const Search = {
  mounted() {
    this.input = this.el.querySelector("input[role=combobox]")
    this.active = 0

    this.input.addEventListener("focus", () => this.open())
    this.input.addEventListener("keydown", event => this.keydown(event))
    this.el.addEventListener("sarduty:search-closed", () => this.closed())

    this.onDocumentKey = event => {
      if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
      if (event.target.closest("input, textarea, select, [contenteditable]")) return
      event.preventDefault()
      // Below 1024px the field is in the closed sheet, and a hidden field can't take focus.
      // open() adds the class in the next frame, so focus in a frame after it.
      this.open()
      window.requestAnimationFrame(() => this.input.focus())
    }
    this.onDocumentClick = event => {
      if (this.isOpen() && !this.el.querySelector(".site-search-box").contains(event.target)) {
        if (event.target.closest(`#${this.el.id}-open`)) return
        this.close()
      }
    }
    document.addEventListener("keydown", this.onDocumentKey)
    document.addEventListener("click", this.onDocumentClick)
  },

  updated() {
    this.highlight(0)
  },

  destroyed() {
    document.removeEventListener("keydown", this.onDocumentKey)
    document.removeEventListener("click", this.onDocumentClick)
  },

  isOpen() {
    return this.el.classList.contains("is-open")
  },

  options() {
    return [...this.el.querySelectorAll("[role=option]")]
  },

  open() {
    this.js().addClass(this.el, "is-open")
    this.js().setAttribute(this.input, "aria-expanded", "true")
    this.highlight(this.active)
  },

  close() {
    this.js().removeClass(this.el, "is-open")
    this.closed()
  },

  // After Esc, Cancel, or a click on the dimmed page.
  closed() {
    this.js().setAttribute(this.input, "aria-expanded", "false")
    this.js().removeAttribute(this.input, "aria-activedescendant")
    this.input.blur()
  },

  keydown(event) {
    const options = this.options()
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        return this.highlight(Math.min(this.active + 1, options.length - 1))
      case "ArrowUp":
        event.preventDefault()
        return this.highlight(Math.max(this.active - 1, 0))
      case "Enter":
        // With nothing listed yet, the form submits and the server opens the best result.
        if (options[this.active]) {
          event.preventDefault()
          options[this.active].click()
        }
        return
      case "Escape":
        event.preventDefault()
        return this.close()
    }
  },

  highlight(index) {
    const options = this.options()
    this.active = Math.max(0, Math.min(index, options.length - 1))
    options.forEach((option, i) => {
      this.js().setAttribute(option, "aria-selected", i === this.active ? "true" : "false")
    })
    const option = options[this.active]
    if (option) {
      this.js().setAttribute(this.input, "aria-activedescendant", option.id)
      option.scrollIntoView({block: "nearest"})
    } else {
      this.js().removeAttribute(this.input, "aria-activedescendant")
    }
  },
}
