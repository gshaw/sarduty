// The style guide's own script. Its pages are not LiveViews, so hooks that the examples
// need are mounted here by hand.
import {Combobox} from "./combobox"
import {listenForConfirms} from "./confirm_dialog"
import {RichText} from "./rich_text"
import {Search} from "./search"
// The top bar's Log out is a DELETE link, which phoenix_html sends.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

// The top bar's search is the one LiveView here (Web.StyleGuideSearchLive), with the app's
// Search hook, so it looks and works as the app's does.
const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {Search},
}).connect()

// The Confirm dialog page's examples ask as the app does.
listenForConfirms()

for (const [name, Hook] of Object.entries({Combobox, RichText})) {
  document.querySelectorAll(`[phx-hook=${name}]`).forEach(el => {
    const hook = Object.create(Hook)
    hook.el = el
    hook.mounted()
  })
}

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
