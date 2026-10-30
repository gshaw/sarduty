#!/bin/sh
# Mockup kit: build the app's CSS into tools/mockups/app.css, with its fonts, so mockups
# draw with today's styles. Run it before each round.
set -eu
kit=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$kit/../.." && pwd)
(cd "$root" && MAPBOX_ACCESS_TOKEN=dummy mise exec -- mix assets.build >/dev/null)
# The app serves fonts from /fonts/; a file:// page needs them beside the CSS.
sed 's#url("/fonts/#url("fonts/#g' "$root/priv/static/assets/css/app.css" >"$kit/app.css"
mkdir -p "$kit/fonts"
cp "$root"/priv/static/fonts/*.woff2 "$kit/fonts/"
