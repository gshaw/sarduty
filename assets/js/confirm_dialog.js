// data-confirm asks in our own dialog, not window.confirm (#651): phones can drop
// window.confirm and answer Cancel. phoenix_html asks through a "phoenix.link.click"
// event; this catches it first, and once the person confirms, clicks the button again.
// Web.Components.Messages.confirm_dialog/1 is the markup and lists the data attributes.
export function listenForConfirms() {
  document.querySelectorAll("[data-confirm-dialog]").forEach(watchLock)

  const dialog = document.getElementById("confirm-dialog")
  if (!dialog?.showModal) return
  let pending = null

  // Whether the dialog was opened with a mouse or a finger, not a key.
  let pointer = false
  window.addEventListener("pointerdown", () => { pointer = true }, true)
  window.addEventListener("keydown", () => { pointer = false }, true)
  dialog.addEventListener("keydown", () => { delete dialog.dataset.pointer })

  window.addEventListener("phoenix.link.click", event => {
    const button = event.target
    const message = button.getAttribute?.("data-confirm")
    if (!message) return
    // Keeps phoenix_html's window.confirm from running.
    event.stopPropagation()
    if (button === pending) return
    event.preventDefault()
    dialog.toggleAttribute("data-pointer", pointer)
    ask(dialog, button, message)
  }, true)

  dialog.addEventListener("close", () => {
    const button = dialog.button
    dialog.button = null
    if (dialog.returnValue !== "confirm" || !button?.isConnected) return
    const choices = part(dialog, "choices")
    if (!choices.hidden) {
      button.setAttribute("phx-value-choice", choices.querySelector("input:checked")?.value || "")
    }
    pending = button
    button.click()
    pending = null
  })
}

// The action waits on the check box or the typed text, in the page's dialog and in the
// style guide's examples, which stay open.
function watchLock(dialog) {
  dialog.addEventListener("input", () => lock(dialog))
  dialog.addEventListener("change", () => lock(dialog))
  if (dialog.id !== "confirm-dialog") {
    dialog.querySelector("form").addEventListener("submit", event => event.preventDefault())
  }
}

function lock(dialog) {
  const check = part(dialog, "check")
  const type = part(dialog, "type")
  const unticked = !check.hidden && !check.querySelector("input").checked
  const unmatched = !type.hidden &&
    key(type.querySelector("input").value) !== key(type.querySelector("code").textContent)
  action(dialog).disabled = unticked || unmatched
}

const key = text => text.toLowerCase().replace(/\s+/g, "")
const part = (dialog, name) => dialog.querySelector(`[data-part=${name}]`)
const action = dialog => dialog.querySelector("button[value=confirm]")

function ask(dialog, button, message) {
  const data = name => button.getAttribute(`data-confirm-${name}`)
  // "Delete MIT 2026? Its rules go too." asks the question and explains after it.
  const [, question, body] = message.match(/^(.*?\?)\s+(.+)$/s) || [null, message, ""]
  const alt = data("alt")

  dialog.button = button
  dialog.returnValue = ""
  dialog.querySelector(".confirm-dialog-question").textContent = question
  fill(part(dialog, "body"), body)
  fill(part(dialog, "warning"), data("warning"))

  const list = part(dialog, "list")
  const items = JSON.parse(data("list") || "[]")
  list.replaceChildren(...items.map(item => Object.assign(document.createElement("li"), {textContent: item})))
  list.hidden = items.length === 0

  const check = part(dialog, "check")
  check.hidden = !data("check")
  check.querySelector("input").checked = false
  check.querySelector("span").textContent = data("check") || ""

  const type = part(dialog, "type")
  type.hidden = !data("type")
  type.querySelector("label").textContent = data("type-label") || "Type this to confirm"
  type.querySelector("code").textContent = data("type") || ""
  type.querySelector("input").value = ""

  // Radios the action needs an answer from, such as how long to snooze.
  const choices = part(dialog, "choices")
  const options = JSON.parse(data("choices") || "[]")
  const picked = data("choice") || options[0]?.[0]
  choices.hidden = options.length === 0
  choices.querySelector("legend").textContent = data("choices-label") || ""
  choices.querySelector("div").replaceChildren(...options.map(([value, text]) => {
    const label = Object.assign(document.createElement("label"), {className: "choice"})
    const input = Object.assign(document.createElement("input"),
      {type: "radio", name: `${dialog.id}-choice`, value, checked: value === picked})
    label.append(input, Object.assign(document.createElement("span"), {textContent: text}))
    return label
  }))

  const link = part(dialog, "alt")
  fill(link, alt)
  link.href = data("alt-href") || "#"

  // Red for a delete, blue otherwise; with a better way out, that's the blue one.
  const confirm = action(dialog)
  const danger = button.classList.contains("btn-danger") || button.hasAttribute("data-confirm-danger")
  confirm.className = ["btn", danger ? "btn-danger" : alt ? null : "btn-primary"].filter(Boolean).join(" ")
  confirm.textContent = data("button") || button.textContent.replace(/\s+/g, " ").trim()
  lock(dialog)

  // Cancel takes focus, so Return cancels, as Apple's alerts do for a delete. Opened
  // with a mouse or a finger it keeps its own look until a key is pressed (messages.css).
  dialog.showModal()
  ;(type.hidden ? dialog.querySelector("button[value=cancel]") : type.querySelector("input")).focus()
}

function fill(element, text) {
  element.textContent = text || ""
  element.hidden = !text
}
