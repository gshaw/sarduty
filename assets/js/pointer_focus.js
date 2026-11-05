// Yellow focus means the keyboard. Browsers also show it on a button a script focuses,
// such as a dialog's Cancel, right after a click or a tap. <html data-pointer> says the
// last thing done was a click or a tap, until a key is pressed, and btn.css keeps a
// focused button's own look while it's there. Every dialog gets this with nothing to add.
//
// Only a key that works the page counts. A modifier alone, or a ⌘ or Ctrl shortcut,
// moves no focus: ⌘⇧4 for a screenshot sends ⌘ and ⇧ to the page, and once turned
// Cancel yellow in every screenshot of a confirm.
const MODIFIERS = new Set(["Shift", "Meta", "Control", "Alt", "AltGraph", "CapsLock", "Fn", "OS"])

const worksPage = event =>
  !MODIFIERS.has(event.key) && !event.metaKey && !event.ctrlKey

export function trackPointer() {
  const root = document.documentElement
  window.addEventListener("pointerdown", () => { root.dataset.pointer = "" }, true)
  window.addEventListener("keydown", event => {
    if (worksPage(event)) delete root.dataset.pointer
  }, true)
}
