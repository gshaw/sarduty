// An Open in maps button (Web.Components.OpenInMaps). It opens the maps app picked last
// on this device, Google Maps until someone picks. Picking one in the menu opens it and
// remembers it for every such button.
const KEY = "sarduty:maps-app"
const NAMES = {google: "Google Maps", apple: "Apple Maps"}

function picked() {
  try {
    return localStorage.getItem(KEY) === "apple" ? "apple" : "google"
  } catch {
    return "google"
  }
}

export const MapPick = {
  mounted() {
    this.el.addEventListener("click", event => {
      const choice = event.target.closest("[data-map-pick]")
      if (!choice) return
      try { localStorage.setItem(KEY, choice.dataset.mapPick) } catch { return }
      window.dispatchEvent(new Event("sarduty:maps-app"))
    })
    this.onPick = () => this.show()
    window.addEventListener("sarduty:maps-app", this.onPick)
    this.show()
  },
  updated() {
    this.show()
  },
  destroyed() {
    window.removeEventListener("sarduty:maps-app", this.onPick)
  },
  // The server renders Google Maps; this puts back the device's pick after each render.
  show() {
    const app = picked()
    const open = this.el.querySelector("[data-map-open]")
    open.href = open.dataset[app]
    open.querySelector("[data-map-name]").textContent = NAMES[app]
    for (const item of this.el.querySelectorAll("[data-map-pick]")) {
      item.setAttribute("aria-checked", String(item.dataset.mapPick === app))
    }
  },
}
