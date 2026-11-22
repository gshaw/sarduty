// The theme switch (Web.Components.ThemeSwitch). A choice posts its form once the knob has
// slid, and Web.ThemeController saves it and comes back to the page with a toast. A full
// load, not a LiveView event: after a click Safari stops sampling the page for its
// toolbar colour until the next load (#656).

const SLIDE_MS = 150

export const listenForThemeChoices = () => {
  document.addEventListener("change", event => {
    const form = event.target.closest("form[data-theme-form]")
    if (form) setTimeout(() => form.submit(), SLIDE_MS)
  })
}
