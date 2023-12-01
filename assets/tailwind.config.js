// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/sartask_web.ex",
    "../lib/sartask_web/**/*.*ex"
  ],
  theme: {
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
    extend: {
      colors: {
        brand: "#FD4F00", // phoenix-orange
      }
    },

  },
  daisyui: {
    themes: [
      {
        nhsuk: {
          // nhsuk-text-color #212b32 (black)
          // nhsuk-secondary-text-color #4c6272 (dark gray)
          // nhsuk-link-color #005eb8 (blue)
          // nhsuk-link-hover-color #7C2855 (dark-pink)
          // nhsuk-link-visited-color #330072 (purple)
          // nhsuk-link-active-color #002f5c (active link)
          // nhsuk-focus-color #ffeb3b (yellow)
          // nhsuk-focus-text-color #212b32 (text-color)
          // nhsuk-border-color #d8dde0 (gray-4)
          // nhsuk-form-border-color #4c6272 (secondary-text-color)
          // nhsuk-error-color #d5281b (red)
          // nhsuk-button-color #007f3b (green)
          // nhsuk-secondary-button-color #4c6272 (gray-1)
          "primary": "#005eb8", // blue-600
          "primary-content": "#ffffff",
          "secondary": "#4c6272",
          "secondary-content": "#ffffff",
          "accent": "#ffb81C", // warm-yello (brand)
          "accent-content": "#212b32",
          "neutral": "#374151", // gray-700
          "neutral-content": "#ffffff",
          "base-content": "#212b32",
          "base-100": "#f3f4f6", // gray-100
          "base-200": "#e5e7eb", // gray-200
          "base-300": "#d1d5db", // gray-300
          "info": "#e5e7eb", // gray-200
          "info-content": "#212b32",
          "success": "#007f3b", // green
          "success-content": "#ffffff",
          "warning": "#ffeb3b", // yellow
          "warning-content": "#212b32",
          "error": "#d5281b", // red
          "error-content": "#ffffff",
        },
        tailwind: {
          "primary": "#2563eb", // blue-600
          "primary-content": "#ffffff",
          "secondary": "#ffffff",
          "secondary-content": "#212b32",
          "accent": "#FD4F00", // phoenix-orange (brand)
          "accent-content": "#ffffff",
          "neutral": "#374151", // gray-700
          "neutral-content": "#ffffff",
          "base-content": "#212b32",
          "base-100": "#f3f4f6", // gray-100
          "base-200": "#e5e7eb", // gray-200
          "base-300": "#d1d5db", // gray-300
          "info": "#e5e7eb", // gray-200
          "info-content": "#212b32",
          "success": "#16a34a", // green-600
          "success-content": "#ffffff",
          "warning": "#facc15", // yellow-400
          "warning-content": "#212b32",
          "error": "#dc2626", // red-600
          "error-content": "#ffffff",
        }
      }
    ],
  },
  plugins: [
    require("daisyui"),
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
