// data-confirm asks in our own dialog, not window.confirm. Some phone browsers, in-app
// ones especially, drop window.confirm and answer Cancel, so the button did nothing.
// phoenix_html asks through a "phoenix.link.click" event; this catches it first. The
// action button repeats the clicked button's label and colour; the other is Cancel.
export function listenForConfirms() {
  // Web.Components.Messages.confirm_dialog/1, in the root layout.
  const dialog = document.getElementById("confirm-dialog")
  if (!dialog?.showModal) return
  let pending = null

  window.addEventListener("phoenix.link.click", event => {
    const button = event.target
    const message = button.getAttribute("data-confirm")
    if (!message) return
    // Keeps phoenix_html's window.confirm from running.
    event.stopPropagation()
    if (button === pending) {
      pending = null
      return
    }
    event.preventDefault()
    ask(dialog, button, message)
  }, true)

  dialog.addEventListener("close", () => {
    const button = dialog.button
    dialog.button = null
    if (dialog.returnValue !== "confirm" || !button?.isConnected) return
    pending = button
    button.click()
    pending = null
  })
}

function ask(dialog, button, message) {
  dialog.button = button
  dialog.returnValue = ""
  dialog.querySelector("p").textContent = message
  const confirm = dialog.querySelector("[value=confirm]")
  confirm.textContent = button.textContent.replace(/\s+/g, " ").trim()
  const variant = [...button.classList].find(name => /^btn-(danger|warning|success|primary)$/.test(name))
  confirm.className = ["btn", variant || "btn-primary"].join(" ")
  dialog.showModal()
  confirm.focus()
}
