const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

// The app's icons: Lucide's, copied into assets/icons by bin/icons, one 24px SVG each.
// Each becomes a variable, --icon-<name>, and a class, .icon-<name>, that <.icon> sets;
// the .icon class in components/icon.css draws it. Every icon is built, not only the ones
// Tailwind finds in a template, because <.icon> puts the name together; a test keeps the
// folder to the icons the app uses.
//
// Lucide draws 2px lines on its 24px grid, so they thin out at 16px. Non-scaling strokes
// keep every line 1.5px at any size, close to the weight of body text.
const STROKE = "1.5"

function url(svg) {
  let content = svg
    .replace(/<!--.*?-->/gs, "")
    .replace(/<svg[^>]*>/, tag => tag.replace(/\s(width|height)="\d+"/g, ""))
    .replace(/stroke-width="[^"]*"/, `stroke-width="${STROKE}"`)
    .replace(/>/, "><style>*{vector-effect:non-scaling-stroke}</style>")
    .replace(/\s+/g, " ")
    .trim()
  return `url('data:image/svg+xml;utf8,${encodeURIComponent(content)}')`
}

module.exports = plugin(function({addBase}) {
  let dir = path.join(__dirname, "../icons")
  let icons = fs.readdirSync(dir).filter(file => file.endsWith(".svg"))

  let vars = {}
  let classes = {}
  icons.forEach(file => {
    let name = path.basename(file, ".svg")
    vars[`--icon-${name}`] = url(fs.readFileSync(path.join(dir, file), "utf8"))
    classes[`.icon-${name}`] = {"--icon": `var(--icon-${name})`}
  })

  addBase({":root": vars, ...classes})
})
