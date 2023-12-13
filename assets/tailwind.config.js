// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/web.ex",
    "../lib/web/**/*.*ex"
  ],
  theme: {
    extend: {
      colors: {
        base: {
          0: "#ffffff", // white
          1: "#fafafa", // zinc-50
          2: "#f4f4f5", // zinc-100
          3: "#e4e4e7", // zinc-200
          content: "#27272a" // zinc-800
        },
        primary: {
          1: "#2563eb", // blue-600
          2: "#1d4ed8", // blue-700
          content: "#fff"
        },
        secondary: {
          1: "#52525b", // zinc-600
          2: "#3f3f46", // zinc-700
          content: "#fff"
        },
        success: {
          1: "#16a34a", // green-600
          2: "#15803d", // green-700
          content: "#fff"
        },
        warning: {
          1: "#fde047", // yellow-300
          2: "#facc15", // yellow-400
          content: "#27272a" // zinc-800
        },
        danger: {
          1: "#dc2626", // red-600
          2: "#b91c1c", // red-700
          content: "#fff"
        },
      }
    },
    screens: {
      md: "640px",
      lg: "960px",
      print: { raw: "print" }
    },
    maxWidth: {
      narrow: "420px",
      sm: "640px",
      md: "960px",
      lg: "1200px"
    },
  },

  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({addVariant}) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function({matchComponents, theme}) {
      let iconsDir = path.join(__dirname, "./vendor/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
        })
      })
      matchComponents({
        "hero": ({name, fullPath}) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": theme("spacing.5"),
            "height": theme("spacing.5")
          }
        }
      }, {values})
    })
  ]
}
