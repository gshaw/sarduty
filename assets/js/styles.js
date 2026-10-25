// The style guide's own script. Its pages are not LiveViews, so hooks that the examples
// need are mounted here by hand.
import {Combobox} from "./combobox"
// The top bar's Log out is a DELETE link, which phoenix_html sends.
import "phoenix_html"

document.querySelectorAll("[phx-hook=Combobox]").forEach(el => {
  const hook = Object.create(Combobox)
  hook.el = el
  hook.mounted()
})

// The filter bar's Filters and Show buttons run LiveView JS commands, which need a
// LiveView, so here they toggle the panel themselves.
document.querySelectorAll(".filter-bar").forEach(bar => {
  const toggle = bar.querySelector(".filter-bar-toggle")
  bar.querySelectorAll(".filter-bar-toggle, .filter-bar-done .btn").forEach(button => {
    button.addEventListener("click", () => {
      const open = bar.classList.toggle("is-open")
      toggle.setAttribute("aria-expanded", open)
    })
  })
})
