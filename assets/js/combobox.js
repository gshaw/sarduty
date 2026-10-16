// A select you type into (#324). The hook's element holds a hidden <select>, which the
// form submits and the server renders, and a text box with an empty list beside it, under
// phx-update="ignore". Typing lists the select's options that contain every word typed;
// picking one sets the select and fires its input event, so phx-change still runs. The
// ARIA follows the WAI combobox pattern: focus stays in the text box and
// aria-activedescendant names the highlighted option.
export const Combobox = {
  mounted() {
    this.select = this.el.querySelector("select")
    this.input = this.el.querySelector("input[role=combobox]")
    this.list = this.el.querySelector("[role=listbox]")
    this.active = -1
    this.syncText()

    // The text box has no name: keep its typing out of the form's phx-change.
    for (const type of ["input", "change"]) {
      this.input.addEventListener(type, event => {
        event.stopPropagation()
        if (type !== "input") return
        if (this.input.value !== this.selectedLabel()) this.select.value = ""
        this.open()
      })
    }
    this.input.addEventListener("click", () => (this.isOpen() ? this.close() : this.open(true)))
    this.input.addEventListener("keydown", event => this.keydown(event))
    this.input.addEventListener("blur", () => {
      this.close()
      this.syncText()
    })
    // Keep focus in the text box while the pointer picks an option.
    this.list.addEventListener("mousedown", event => event.preventDefault())
    this.list.addEventListener("click", event => {
      const option = event.target.closest("[role=option]")
      if (option) this.pick(option)
    })

    // The server changes the options, or the value after a save.
    this.observer = new MutationObserver(() => {
      if (this.isOpen()) this.render(this.input.value)
      else this.syncText()
    })
    this.observer.observe(this.select, {childList: true, subtree: true, attributes: true})
  },

  updated() {
    if (!this.isOpen()) this.syncText()
  },

  destroyed() {
    this.observer?.disconnect()
  },

  keydown(event) {
    const options = this.options()
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        if (!this.isOpen()) return this.open(true)
        return this.highlight(Math.min(this.active + 1, options.length - 1))
      case "ArrowUp":
        event.preventDefault()
        return this.highlight(Math.max(this.active - 1, 0))
      case "Enter":
        // Enter picks the highlighted option; with the list closed it submits the form.
        if (this.isOpen() && options[this.active]) {
          event.preventDefault()
          this.pick(options[this.active])
        }
        return
      case "Escape":
        if (this.isOpen()) {
          event.preventDefault()
          this.close()
        }
        return
    }
  },

  // all: list every option, not just those matching the text, as when the box is clicked.
  open(all = false) {
    this.render(all && this.input.value === this.selectedLabel() ? "" : this.input.value)
    this.list.hidden = false
    this.input.setAttribute("aria-expanded", "true")
  },

  close() {
    this.list.hidden = true
    this.input.setAttribute("aria-expanded", "false")
    this.input.removeAttribute("aria-activedescendant")
    this.active = -1
  },

  isOpen() {
    return !this.list.hidden
  },

  options() {
    return [...this.list.querySelectorAll("[role=option]")]
  },

  render(text) {
    const words = text.toLowerCase().split(/\s+/).filter(Boolean)
    const items = []
    let count = 0

    for (const child of this.select.children) {
      const options = child.tagName === "OPTGROUP" ? [...child.children] : [child]
      const matches = options.filter(o => o.value !== "" && words.every(w => o.text.toLowerCase().includes(w)))
      if (matches.length === 0) continue
      if (child.tagName === "OPTGROUP") items.push(this.groupItem(child.label))
      for (const option of matches) items.push(this.optionItem(option, words, count++))
    }

    if (count === 0) {
      const empty = document.createElement("li")
      empty.className = "combobox-empty"
      empty.textContent = text.trim() ? `Nothing matches "${text.trim()}".` : "Nothing to add."
      items.push(empty)
    }

    this.list.replaceChildren(...items)
    this.highlight(count > 0 && words.length > 0 ? 0 : -1)
  },

  groupItem(label) {
    const li = document.createElement("li")
    li.className = "combobox-group caps"
    li.setAttribute("role", "presentation")
    li.textContent = label
    return li
  },

  optionItem(option, words, index) {
    const li = document.createElement("li")
    li.id = `${this.input.id}-option-${index}`
    li.className = "combobox-option"
    li.setAttribute("role", "option")
    li.setAttribute("aria-selected", "false")
    li.dataset.value = option.value
    li.append(...this.marked(option.text, words))
    return li
  },

  // The option's text with each typed word in a <mark>. Built from text nodes, never HTML.
  marked(text, words) {
    const lower = text.toLowerCase()
    const hits = Array(text.length).fill(false)
    for (const word of words) {
      const at = lower.indexOf(word)
      if (at >= 0) hits.fill(true, at, at + word.length)
    }

    const nodes = []
    let start = 0
    for (let i = 1; i <= text.length; i++) {
      if (i < text.length && hits[i] === hits[start]) continue
      const part = text.slice(start, i)
      if (hits[start]) {
        const mark = document.createElement("mark")
        mark.textContent = part
        nodes.push(mark)
      } else {
        nodes.push(document.createTextNode(part))
      }
      start = i
    }
    return nodes
  },

  highlight(index) {
    const options = this.options()
    options.forEach((o, i) => o.setAttribute("aria-selected", String(i === index)))
    this.active = index
    const option = options[index]
    if (option) {
      this.input.setAttribute("aria-activedescendant", option.id)
      option.scrollIntoView({block: "nearest"})
    } else {
      this.input.removeAttribute("aria-activedescendant")
    }
  },

  pick(option) {
    this.select.value = option.dataset.value
    this.input.value = this.selectedLabel()
    this.close()
    this.select.dispatchEvent(new Event("input", {bubbles: true}))
    this.select.dispatchEvent(new Event("change", {bubbles: true}))
  },

  selectedLabel() {
    const option = this.select.selectedOptions[0]
    return option && option.value !== "" ? option.text : ""
  },

  // The text box shows the picked option. Typing clears the select, so text left
  // without a pick shows nothing rather than sending an option the person did not pick.
  syncText() {
    this.input.value = this.selectedLabel()
  },
}
