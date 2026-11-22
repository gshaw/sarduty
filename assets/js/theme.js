// The theme switch (Web.Components.ThemeSwitch). A choice goes in the `theme` cookie, which
// Web.Theme reads so the server renders data-theme. System deletes the cookie. Chrome keeps
// a cookie 400 days at most, so each page load saves it again.
//
// A choice reloads the page: after a click Safari stops sampling the page for its toolbar
// colour until the next load (#656), so without one the toolbar keeps the old theme. The
// theme applies first, so a page that asks before leaving still shows it if you stay.

const MAX_AGE = 400 * 24 * 60 * 60

const saveTheme = theme => {
  const secure = location.protocol === "https:" ? "; Secure" : ""
  const age = theme ? MAX_AGE : 0
  document.cookie = `theme=${theme}; Path=/; Max-Age=${age}; SameSite=Lax${secure}`
}

const markThemeChoices = (root = document) => {
  const current = document.documentElement.dataset.theme || ""
  root.querySelectorAll("[data-theme-choice]").forEach(button => {
    button.setAttribute("aria-pressed", button.dataset.themeChoice === current)
  })
}

const setTheme = theme => {
  if (theme) document.documentElement.dataset.theme = theme
  else delete document.documentElement.dataset.theme
  saveTheme(theme)
  markThemeChoices()
  location.reload()
}

export const listenForThemeChoices = () => {
  document.addEventListener("click", event => {
    const button = event.target.closest("[data-theme-choice]")
    if (button) setTheme(button.dataset.themeChoice)
  })
  const theme = document.documentElement.dataset.theme
  if (theme) saveTheme(theme)
  markThemeChoices()
}

export const ThemeSwitch = {
  mounted() { markThemeChoices(this.el) },
}
