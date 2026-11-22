// The theme switch (Web.Components.ThemeSwitch). A choice applies at once and goes in the
// `theme` cookie, which Web.Theme reads so the server renders data-theme on the next page.
// System deletes the cookie. Chrome keeps a cookie 400 days at most, so each page load
// saves it again.

const MAX_AGE = 400 * 24 * 60 * 60

const saveTheme = theme => {
  const secure = location.protocol === "https:" ? "; Secure" : ""
  const age = theme ? MAX_AGE : 0
  document.cookie = `theme=${theme}; Path=/; Max-Age=${age}; SameSite=Lax${secure}`
}

// Each meta's data-system is the navy for its own scheme, from Web.Layouts.theme_colors.
const showThemeColor = theme => {
  const tags = document.querySelectorAll('meta[name="theme-color"]')
  const navy = scheme => [...tags].find(m => m.media.includes(scheme))?.dataset.system
  tags.forEach(meta => { meta.content = theme ? navy(theme) : meta.dataset.system })
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
  showThemeColor(theme)
  markThemeChoices()
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
