const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

// Heroicons, as hero-* classes, and the app's own icons in assets/icons, as sd-* classes,
// for the few Heroicons has none of. Both use Heroicons' folders and suffixes.
const styles = [
  ["", "/24/outline", "24px"],
  ["-solid", "/24/solid", "24px"],
  ["-mini", "/20/solid", "20px"],
  ["-micro", "/16/solid", "16px"]
]

function read(iconsDir) {
  let values = {}
  styles.forEach(([suffix, dir, size]) => {
    let full = path.join(iconsDir, dir)
    if (!fs.existsSync(full)) return
    fs.readdirSync(full).forEach(file => {
      let name = path.basename(file, ".svg") + suffix
      let content = fs.readFileSync(path.join(full, file)).toString().replace(/\r?\n|\r/g, "")
      values[name] = {name, size, url: `url('data:image/svg+xml;utf8,${encodeURIComponent(content)}')`}
    })
  })
  return values
}

// Each style's own size, so an icon needs no size class.
function icon(prefix, {name, size, url}) {
  return {
    [`--${prefix}-${name}`]: url,
    "-webkit-mask": `var(--${prefix}-${name})`,
    "mask": `var(--${prefix}-${name})`,
    "mask-repeat": "no-repeat",
    "background-color": "currentColor",
    "vertical-align": "middle",
    "display": "inline-block",
    "width": size,
    "height": size
  }
}

module.exports = plugin(function({matchComponents, addBase}) {
  let hero = read(path.join(__dirname, "../../deps/heroicons/optimized"))
  let own = read(path.join(__dirname, "../icons"))

  matchComponents({"hero": value => icon("hero", value)}, {values: hero})
  matchComponents({"sd": value => icon("sd", value)}, {values: own})

  // The app's own icons as variables too, so a button can draw one in its ::before
  // (<.button icon>), where phx-disable-with leaves it alone.
  addBase({":root": Object.fromEntries(Object.values(own).map(v => [`--sd-${v.name}`, v.url]))})
})
