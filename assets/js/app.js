// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/sarduty"
import topbar from "../vendor/topbar"
import {listenForConfirms} from "./confirm_dialog"
import {QRScanner} from "./qr_scanner"
import {SoundSwitch, listenForScanSounds} from "./scan_sound"
import {Combobox} from "./combobox"
import {FileDrop} from "./file_drop"
import {SelectAll} from "./select_all"
import {ScannerInput} from "./scanner_input"
import {RichText} from "./rich_text"
import {Search} from "./search"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Combobox, FileDrop, QRScanner, RichText, ScannerInput, Search, SelectAll, SoundSwitch},
})

listenForConfirms()
listenForScanSounds()

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// A button with JS.dispatch("sarduty:copy", to: "#input") copies the input's value, or a
// link's href. With detail: %{status: "#id"}, that element says "Copied" for 2 seconds.
// Where the browser will not copy, an input's text is selected instead.
window.addEventListener("sarduty:copy", async event => {
  const input = event.target
  try {
    await navigator.clipboard.writeText(input.value ?? input.href)
  } catch {
    input.select?.()
    return
  }
  const status = event.detail?.status && document.querySelector(event.detail.status)
  if (!status) return
  status.textContent = "Copied"
  clearTimeout(status.copiedTimer)
  status.copiedTimer = setTimeout(() => { status.textContent = "" }, 2000)
})

// A button with JS.dispatch("sarduty:clear", to: "#input") empties the input, and the
// inputs in detail: %{also: "#a, #b"}, puts the cursor back, then sends the input event
// so the form's phx-change runs. LiveView keeps a focused input's value, so the server
// can't clear it. Focus comes first: an input's phx-focus shares its phx-debounce timer,
// so a focus after the input event would drop the change.
window.addEventListener("sarduty:clear", event => {
  const input = event.target
  const also = event.detail?.also ? document.querySelectorAll(event.detail.also) : []
  for (const other of also) other.value = ""
  input.value = ""
  input.focus()
  input.dispatchEvent(new Event("input", {bubbles: true}))
})

// "`" anywhere outside a field opens the team switcher, or closes it, the way "/" jumps to
// the search. Unadvertised: a shortcut to SAR Duty admin and the style guide. Focus goes to
// the first row, so Tab and Enter pick one; Escape closes it.
window.addEventListener("keydown", event => {
  if (event.metaKey || event.ctrlKey || event.altKey) return
  if (event.target.closest?.("input, textarea, select, [contenteditable]")) return
  const switcher = [...document.querySelectorAll("#team-switcher, #phone-team-switcher")]
    .find(details => details.checkVisibility())
  if (!switcher) return
  if (event.key === "`") {
    event.preventDefault()
    switcher.open = !switcher.open
    if (switcher.open) switcher.querySelector("a")?.focus()
  } else if (event.key === "Escape" && switcher.open) {
    switcher.open = false
    switcher.querySelector("summary").focus()
  }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

