// Keys for the top bar's menus, in the app and the style guide, which share the bar.
//
// "`" anywhere outside a field opens the team switcher, or closes it, the way "/" jumps to
// the search. Unadvertised: a shortcut to SAR Duty admin and the style guide. Focus goes to
// the first row, so the arrow keys, Tab, and Enter pick one; Escape closes it.
export function listenForBarMenuKeys() {
  window.addEventListener("keydown", event => {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (moveInBarMenu(event)) return
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
}

// Up and Down move through the rows of an open menu in the top bar, the team switcher or
// your account, from its button or a row, as they do through the search's results. Home
// and End go to the first and last. Returns true when it moved.
function moveInBarMenu(event) {
  const keys = ["ArrowDown", "ArrowUp", "Home", "End"]
  if (!keys.includes(event.key)) return false
  const menu = event.target.closest?.("details[name=site-bar][open]")
  if (!menu) return false
  const rows = [...menu.querySelectorAll("a, button")].filter(row => row.checkVisibility())
  if (rows.length === 0) return false
  const at = rows.indexOf(document.activeElement)
  const next = {
    ArrowDown: at < 0 ? 0 : (at + 1) % rows.length,
    ArrowUp: at < 0 ? rows.length - 1 : (at - 1 + rows.length) % rows.length,
    Home: 0,
    End: rows.length - 1,
  }[event.key]
  event.preventDefault()
  rows[next].focus()
  return true
}
