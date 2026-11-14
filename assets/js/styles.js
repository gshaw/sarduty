// The style guide's own script. Its pages are not LiveViews, so hooks that the examples
// need are mounted here by hand.
import {listenForBarMenuKeys} from "./bar_menu_keys"
import {Combobox} from "./combobox"
import {DragList} from "./drag_list"
import {listenForConfirms} from "./confirm_dialog"
import {RichText} from "./rich_text"
import {Search} from "./search"
import {hideImagesOnError} from "./hide_on_error"
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

// The bar's ` key and arrow keys, as in the app.
listenForBarMenuKeys()

// A drag list here has no LiveView to tell, so its rows only move on the page.
for (const [name, Hook] of Object.entries({Combobox, DragList, RichText})) {
  document.querySelectorAll(`[phx-hook=${name}]`).forEach(el => {
    const hook = Object.create(Hook)
    hook.el = el
    hook.pushEvent = () => {}
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

// Photos that fail to load show the initials under them, as in the app.
hideImagesOnError()

// The examples' forms show how a form looks; submitting one goes nowhere.
document.addEventListener("submit", event => {
  if (event.target.closest("[data-example-form]")) event.preventDefault()
})

// iOS Safari only applies :active, the pressed look, when a touch listener exists.
document.addEventListener("touchstart", () => {}, {passive: true})

// The theme buttons. styles_theme.js applied the saved theme before first paint.
const themeButtons = document.querySelectorAll("[data-theme-choice]")
const showTheme = () => {
  const current = document.documentElement.dataset.theme || ""
  themeButtons.forEach(b => b.setAttribute("aria-pressed", b.dataset.themeChoice === current))
}
themeButtons.forEach(button => {
  button.addEventListener("click", () => {
    const theme = button.dataset.themeChoice
    if (theme) {
      document.documentElement.dataset.theme = theme
      localStorage.setItem("styles-theme", theme)
    } else {
      delete document.documentElement.dataset.theme
      localStorage.removeItem("styles-theme")
    }
    window.setThemeColor(theme)
    showTheme()
  })
})
showTheme()

// The phone's Menu opens at the page you're on, not 30 pages above it.
const phoneMenu = document.getElementById("phone-menu")
phoneMenu?.addEventListener("toggle", () => {
  const panel = phoneMenu.querySelector(".site-bar-phone-panel")
  const current = panel.querySelector('[aria-current="page"]')
  if (phoneMenu.open && current) panel.scrollTop = current.offsetTop - panel.clientHeight / 2
})

// The Top bar page: open the menus, so the examples show them. Their shared name would
// let only one stay open, so drop it here.
document
  .querySelectorAll(
    ".bar-demo .team-switcher, .phone-bar-demo:not(.switcher-demo) .site-bar-phone, .switcher-demo .phone-team-switcher",
  )
  .forEach(menu => {
    menu.removeAttribute("name")
    menu.open = true
  })

// The Toast page: each button shows a sample toast.
document.querySelectorAll("[data-toast]").forEach(button => {
  button.addEventListener("click", () => {
    const kind = button.dataset.toast
    const toast = document.getElementById("toast-" + kind).content.firstElementChild.cloneNode(true)
    toast.removeAttribute("id")
    document.getElementById("toasts").appendChild(toast)
    toast.addEventListener("click", () => toast.remove())
    if (kind !== "error") setTimeout(() => toast.remove(), 6000)
  })
})
