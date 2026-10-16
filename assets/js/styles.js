// The style guide's own script. Its pages are not LiveViews, so hooks that the examples
// need are mounted here by hand.
import {Combobox} from "./combobox"

document.querySelectorAll("[phx-hook=Combobox]").forEach(el => {
  const hook = Object.create(Combobox)
  hook.el = el
  hook.mounted()
})
