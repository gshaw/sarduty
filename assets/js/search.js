// The top bar's search (#473). The server renders the results; this opens and closes the
// panel, moves through the results with the arrow keys, and opens one with Enter. Focus
// stays in the field and aria-activedescendant names the highlighted result, as in the
// WAI combobox pattern. Classes and attributes go through this.js(), so the server's
// renders keep them. "/" anywhere outside a field jumps to the search, and the glass below
// 1024px opens it.
//
// The browser keeps the last 5 results opened, per person and team, under data-recent-key,
// and sends them to the server on mount, which shows the ones this person can still open.
const RECENT = 5
export const Search = {
  mounted() {
    this.input = this.el.querySelector("input[role=combobox]")
    this.active = 0

    // The glass opens the sheet here rather than with JS commands, which add the class a
    // frame later: the field must be showing and focused within the tap, or iOS won't
    // raise the keyboard. The class survives the server's renders because the component
    // ignores server changes to it (phx-mounted).
    this.el.querySelector(`#${this.el.id}-open`).addEventListener("click", () => {
      this.el.classList.add("is-open")
      this.input.focus()
    })
    // The x clears the field and keeps the keyboard up; the input event runs the search.
    const clear = this.el.querySelector(`#${this.el.id}-clear`)
    clear.addEventListener("pointerdown", event => event.preventDefault())
    clear.addEventListener("click", event => {
      event.preventDefault()
      this.input.value = ""
      this.input.dispatchEvent(new Event("input", {bubbles: true}))
      this.input.focus()
    })

    this.input.addEventListener("focus", () => this.open())
    this.input.addEventListener("keydown", event => this.keydown(event))
    this.el.addEventListener("sarduty:search-closed", () => this.closed())
    // Remember a result as it opens, by a click or by Enter, which clicks it.
    this.el.addEventListener("click", event => {
      const option = event.target.closest("[role=option][data-key]")
      if (option) this.remember(option.dataset.key)
    })
    const keys = this.recentKeys()
    if (keys.length) this.pushEventTo(this.el, "recent", {keys})

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

  recentKeys() {
    try {
      const keys = JSON.parse(localStorage.getItem(this.el.dataset.recentKey) || "[]")
      return Array.isArray(keys) ? keys.filter(key => typeof key === "string").slice(0, RECENT) : []
    } catch {
      return []
    }
  },

  remember(key) {
    if (!this.el.dataset.recentKey) return
    const keys = [key, ...this.recentKeys().filter(k => k !== key)].slice(0, RECENT)
    try {
      localStorage.setItem(this.el.dataset.recentKey, JSON.stringify(keys))
    } catch {
      // Private browsing can refuse storage; search works without recent picks.
    }
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
