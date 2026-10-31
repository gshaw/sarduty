// Yellow focus means the keyboard. Browsers also show it on a button a script focuses,
// such as a dialog's Cancel, right after a click or a tap. <html data-pointer> says the
// last thing done was a click or a tap, until a key is pressed, and btn.css keeps a
// focused button's own look while it's there. Every dialog gets this with nothing to add.
export function trackPointer() {
  const root = document.documentElement
  window.addEventListener("pointerdown", () => { root.dataset.pointer = "" }, true)
  window.addEventListener("keydown", () => { delete root.dataset.pointer }, true)
}
