// The style guide's saved theme, before first paint so it doesn't flash. A classic
// script in the head, not a module: modules run after the page is parsed. A chosen theme
// also sets the browser's colour, which otherwise follows the system's.
;(function () {
  var navy = {light: "#13243a", dark: "#0a111b"}
  window.setThemeColor = function (theme) {
    document.querySelectorAll('meta[name="theme-color"]').forEach(function (meta) {
      var system = meta.media.indexOf("dark") >= 0 ? "dark" : "light"
      meta.content = navy[theme || system]
    })
  }
  var theme = localStorage.getItem("styles-theme")
  if (theme) document.documentElement.dataset.theme = theme
  window.setThemeColor(theme)
})()
