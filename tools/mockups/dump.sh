#!/bin/sh
# Mockup kit: dump a round's real pages with its dump test (docs/mockups.md).
#   tools/mockups/dump.sh <round>/dump_test.exs
# Copies the test into test/mockups/ for the run only, and writes the pages to
# <round>/real/.
set -eu
round=$(cd "$(dirname "$1")" && pwd)
root=$(cd "$(dirname "$0")/../.." && pwd)
dest="$root/test/mockups/$(basename "$1")"
mkdir -p "$root/test/mockups"
cp "$1" "$dest"
trap 'rm -f "$dest"; rmdir "$root/test/mockups" 2>/dev/null || true' EXIT
cd "$root"
MOCKUP_OUT="$round/real" MAPBOX_ACCESS_TOKEN=dummy mise exec -- mix test "test/mockups/$(basename "$1")"
