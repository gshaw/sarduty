// A photo that fails to load is removed, so the initials under it show
// (img[data-hide-on-error]). In place of onerror="this.remove()", which the
// Content-Security-Policy refuses (Web.CSP). Error events don't bubble, so this listens
// in the capture phase, and sweeps images that failed before the script ran.
export function hideImagesOnError() {
  const hide = img => img.matches("img[data-hide-on-error]") && img.remove()
  document.addEventListener("error", event => event.target instanceof HTMLImageElement && hide(event.target), true)
  document.querySelectorAll("img[data-hide-on-error]").forEach(img => {
    if (img.complete && img.naturalWidth === 0) img.remove()
  })
}
