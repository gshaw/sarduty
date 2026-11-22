// The theme switch (Web.Components.ThemeSwitch). A choice that changes how the page looks
// posts its form once the knob has slid: a full load, since after a click Safari stops
// sampling the page for its toolbar colour until the next one (#656). A choice that looks
// the same, such as Dark when this device is already dark and on System, saves in the
// background with no reload, then fires `theme:saved` on the form for the page to confirm.

const SLIDE_MS = 150

const looks = theme =>
  theme === "light" || theme === "dark"
    ? theme
    : matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"

const saveQuietly = async (form, theme) => {
  const response = await fetch(form.action, {
    method: "POST",
    body: new FormData(form),
    headers: {"x-theme-save": "background"},
  })
  if (!response.ok) return form.submit()
  if (theme === "system") delete document.documentElement.dataset.theme
  else document.documentElement.dataset.theme = theme
  form.dispatchEvent(new CustomEvent("theme:saved", {bubbles: true, detail: {theme}}))
}

export const listenForThemeChoices = () => {
  document.addEventListener("change", event => {
    const form = event.target.closest("form[data-theme-form]")
    if (!form) return
    const theme = event.target.value
    const before = document.documentElement.dataset.theme || "system"
    if (looks(theme) === looks(before)) saveQuietly(form, theme)
    else setTimeout(() => form.submit(), SLIDE_MS)
  })
}

// On a LiveView page, the toast a full load would have shown.
export const ThemeSaved = {
  mounted() {
    this.el.addEventListener("theme:saved", e => this.pushEvent("theme-saved", e.detail))
  },
}
